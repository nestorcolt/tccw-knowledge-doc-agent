from tccw_knowledge_doc_agent.crew import TccwKnowledgeDocAgent
import boto3
import json
import os

# Initialize S3 client outside the handler for reuse
s3_client = boto3.client("s3")

# Get ignored prefixes from environment variable
IGNORED_PREFIXES = os.environ.get("IGNORED_PREFIXES", ".write/").split(",")


def get_and_merge_objects(bucket, prefix):
    """
    Fetches all objects from the given prefix in the bucket and merges their content.

    Args:
        bucket (str): S3 bucket name
        prefix (str): S3 key prefix (folder path)

    Returns:
        str: Merged content of all objects
    """
    print(f"Fetching all objects from bucket {bucket} with prefix {prefix}")

    # Make sure prefix ends with a slash if it's a folder
    if not prefix.endswith("/"):
        prefix = prefix + "/"

    # List all objects with the given prefix
    response = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)

    # If no objects found
    if "Contents" not in response:
        print(f"No objects found in {bucket}/{prefix}")
        return ""

    # Extract all object keys
    object_keys = [obj["Key"] for obj in response["Contents"]]
    print(f"Found {len(object_keys)} objects: {object_keys}")

    # Get and merge content of all objects
    merged_content = ""
    for key in object_keys:
        # Skip if the object is a "folder" (ends with /)
        if key.endswith("/"):
            continue

        print(f"Getting content of {key}")
        obj = s3_client.get_object(Bucket=bucket, Key=key)
        content = obj["Body"].read().decode("utf-8")

        # Add a separator between files
        if merged_content:
            merged_content += "\n\n--- New File ---\n\n"

        merged_content += f"File: {key}\n{content}"

    print(f"Total merged content size: {len(merged_content)} characters")
    return merged_content


def should_ignore(key):
    """
    Checks if the key should be ignored based on ignored prefixes.

    Args:
        key (str): S3 object key

    Returns:
        bool: True if the key should be ignored, False otherwise
    """
    for prefix in IGNORED_PREFIXES:
        if prefix and key.startswith(prefix):
            return True
    return False


def lambda_handler(event, context):
    """
    AWS Lambda handler function triggered by S3 bucket events
    """
    try:
        # Extract bucket and key information from the event
        bucket = event["Records"][0]["s3"]["bucket"]["name"]
        key = event["Records"][0]["s3"]["object"]["key"]

        print(f"Event triggered by file {key} from bucket {bucket}")

        # Check if the key should be ignored
        if should_ignore(key):
            print(f"Ignoring file {key} as it matches an ignored prefix")
            return {
                "statusCode": 200,
                "body": json.dumps(
                    {"message": f"File {key} ignored as it matches an ignored prefix"}
                ),
            }

        # Determine the container prefix (parent folder)
        # If the triggering object is in knowledge_base/felix/file.txt,
        # we want to get all files from knowledge_base/felix/
        path_parts = key.split("/")
        if len(path_parts) <= 1:
            container_prefix = ""
        else:
            # Get the directory containing the file
            container_prefix = "/".join(path_parts[:-1]) + "/"

        print(f"Container prefix: {container_prefix}")

        # Get all objects from this container and merge them
        merged_content = get_and_merge_objects(bucket, container_prefix)

        # Extract a topic from the container name
        topic = "Default Topic"
        if container_prefix:
            # Get the last folder name from the path
            topic = (
                container_prefix.rstrip("/").split("/")[-1].replace("_", " ").title()
            )

        print(f"Using topic: {topic}")

        # Initialize the TccwKnowledgeDocAgent
        agent = TccwKnowledgeDocAgent()

        # Run the agent with the merged content and topic
        result = agent.crew().kickoff(
            inputs={"topic": topic, "content": merged_content}
        )

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Document processing completed successfully",
                    "bucket": bucket,
                    "container": container_prefix,
                    "files_processed": merged_content.count("--- New File ---") + 1,
                    "result": result,
                }
            ),
        }
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({"message": f"Error processing document: {str(e)}"}),
        }
