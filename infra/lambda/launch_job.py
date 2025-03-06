import boto3
import json
import os
import logging
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get("APP_LOG_LEVEL", "INFO"))

# Initialize AWS clients
eventbridge = boto3.client("events")
s3_client = boto3.client("s3")


class Config:
    ENVIRONMENT = {
        "SOURCE_BUCKET_NAME": os.environ.get(
            "SOURCE_BUCKET_NAME", "tccw-work-pipiline-entry"
        ),
        "SOURCE_BUCKET_PREFIX": os.environ.get(
            "SOURCE_BUCKET_PREFIX", "knowledge_base/"
        ),
        "IGNORED_PREFIXES": os.environ.get("IGNORED_PREFIXES", ".write/").split(","),
        "ECS_CLUSTER_NAME": os.environ.get(
            "ECS_CLUSTER_NAME", "tccw-knowledge-doc-agent-cluster"
        ),
        "ECS_TASK_NAME": os.environ.get(
            "ECS_TASK_NAME", "tccw-knowledge-doc-agent-task"
        ),
        "ECS_CONTAINER_NAME": os.environ.get(
            "ECS_CONTAINER_NAME", "tccw-knowledge-doc-agent-container"
        ),
        "EVENT_BUS_NAME": os.environ.get("EVENT_BUS_NAME", "default"),
        "EVENT_SOURCE": os.environ.get("EVENT_SOURCE", "tccw.knowledge.doc.agent"),
        "EVENT_DETAIL_TYPE": os.environ.get("EVENT_DETAIL_TYPE", "S3ObjectCreated"),
    }

    @staticmethod
    def get(key):
        return Config.ENVIRONMENT.get(key)


def should_ignore(key):
    """
    Checks if the key should be ignored based on ignored prefixes.
    """
    for prefix in Config.get("IGNORED_PREFIXES"):
        if prefix and key.startswith(prefix):
            return True
    return False


def extract_inner_directory(key):
    """
    Extracts the inner directory path from a full S3 key.
    For example, if key is "knowledge_base/topic_a/file.txt",
    this will return "knowledge_base/topic_a/"
    """
    # Remove the base prefix if it exists
    base_prefix = Config.get("SOURCE_BUCKET_PREFIX")
    if key.startswith(base_prefix):
        # Keep the base prefix in the result
        path_parts = key.split("/")

        # If there are at least 2 parts (base prefix and something else)
        if len(path_parts) > 1:
            # Get the directory containing the file (include the base prefix)
            directory_path = "/".join(path_parts[:-1]) + "/"
            return directory_path

    # If we can't extract a proper directory, return the original key
    return key


def check_directory_exists(bucket, directory):
    """
    Verify if the directory exists and has content
    """
    try:
        # List objects with the directory prefix
        response = s3_client.list_objects_v2(Bucket=bucket, Prefix=directory, MaxKeys=1)

        # If there are contents, the directory exists
        return "Contents" in response and len(response["Contents"]) > 0
    except Exception as e:
        logger.error(f"Error checking directory {directory}: {str(e)}")
        return False


def put_event_to_eventbridge(bucket, directory):
    """
    Puts an event to EventBridge to trigger the ECS task with the directory path
    """
    detail = {
        "bucket": bucket,
        "key": directory,
        "cluster": Config.get("ECS_CLUSTER_NAME"),
        "taskDefinition": Config.get("ECS_TASK_NAME"),
        "containerName": Config.get("ECS_CONTAINER_NAME"),
    }

    event = {
        "Source": Config.get("EVENT_SOURCE"),
        "DetailType": Config.get("EVENT_DETAIL_TYPE"),
        "Detail": json.dumps(detail),
        "EventBusName": Config.get("EVENT_BUS_NAME"),
    }

    logger.info(f"Putting event to EventBridge: {event}")
    response = eventbridge.put_events(Entries=[event])

    if response.get("FailedEntryCount", 0) > 0:
        logger.error(f"Failed to put event to EventBridge: {response}")
        return False

    logger.info(f"Successfully put event to EventBridge: {response}")
    return True


def lambda_handler(event, context):
    """
    Lambda handler function that processes S3 events and forwards them to EventBridge
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # Track processed directories to avoid duplicate processing
    processed_directories = set()

    # Process S3 event records
    for record in event.get("Records", []):
        # Check if this is an S3 event
        if record.get("eventSource") != "aws:s3":
            logger.warning(f"Skipping non-S3 event: {record}")
            continue

        # Extract bucket and key information
        bucket = record.get("s3", {}).get("bucket", {}).get("name")
        key = record.get("s3", {}).get("object", {}).get("key")

        if not bucket or not key:
            logger.warning(f"Missing bucket or key in S3 event: {record}")
            continue

        # Check if the key starts with the required prefix
        if not key.startswith(Config.get("SOURCE_BUCKET_PREFIX")):
            logger.info(f"Skipping object with key not matching prefix: {key}")
            continue

        # Check if the key should be ignored
        if should_ignore(key):
            logger.info(f"Ignoring file {key} as it matches an ignored prefix")
            continue

        # Extract the directory path from the key
        directory = extract_inner_directory(key)

        # Skip if we've already processed this directory in this batch
        if directory in processed_directories:
            logger.info(f"Skipping already processed directory: {directory}")
            continue

        # Verify the directory exists
        if not check_directory_exists(bucket, directory):
            logger.warning(f"Directory does not exist or is empty: {directory}")
            continue

        # Add to processed set
        processed_directories.add(directory)

        # Put event to EventBridge with the directory path
        success = put_event_to_eventbridge(bucket, directory)

        if not success:
            return {
                "statusCode": 500,
                "body": json.dumps({"message": "Failed to put event to EventBridge"}),
            }

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "message": "Successfully processed S3 events",
                "processed_directories": list(processed_directories),
            }
        ),
    }
