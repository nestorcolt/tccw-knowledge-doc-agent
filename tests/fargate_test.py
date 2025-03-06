import boto3
import uuid
import time
import json
import os
from datetime import datetime

# Configuration
REGION = "eu-west-1"  # Update to match your region
SOURCE_BUCKET = "tccw-work-pipiline-entry"  # Your S3 bucket name
PREFIX = "knowledge_base/"  # Your configured prefix
TEST_CONTENT = """
# Test Document

This is a test document to trigger the knowledge document processing pipeline.

## Section 1
This is some sample content for testing purposes.

## Section 2
More sample content to process.
"""


def upload_test_files():
    """Upload multiple test files to the same directory in S3 to trigger the pipeline"""
    s3 = boto3.client("s3", region_name=REGION)

    # Create a unique directory name
    test_dir_name = f"test_{uuid.uuid4().hex[:8]}"
    test_dir_path = f"{PREFIX}{test_dir_name}/"

    # Create multiple files in the same directory
    file_keys = []
    test_file_key = f"{test_dir_path}document_{uuid.uuid4().hex[:8]}.md"
    file_keys.append(test_file_key)

    print(f"Uploading test file to s3://{SOURCE_BUCKET}/{test_file_key}")

    # Upload the file
    s3.put_object(
        Bucket=SOURCE_BUCKET,
        Key=test_file_key,
        Body="modified_content",
        ContentType="text/markdown",
    )

    return test_dir_path, file_keys


def invoke_lambda_directly(function_name, directory_path):
    """Directly invoke the Lambda function with a simulated S3 event"""
    lambda_client = boto3.client("lambda", region_name=REGION)

    # Create a simulated S3 event for one of the files
    test_file_key = f"{directory_path}document_1.md"
    s3_event = {
        "Records": [
            {
                "eventVersion": "2.1",
                "eventSource": "aws:s3",
                "awsRegion": REGION,
                "eventTime": datetime.now().isoformat(),
                "eventName": "ObjectCreated:Put",
                "s3": {
                    "s3SchemaVersion": "1.0",
                    "bucket": {"name": SOURCE_BUCKET},
                    "object": {
                        "key": test_file_key,
                        "size": len(TEST_CONTENT),
                        "eTag": "test-etag",
                    },
                },
            }
        ]
    }

    print(f"Invoking Lambda function {function_name} directly with simulated S3 event")
    print(f"Event payload: {json.dumps(s3_event, indent=2)}")

    # Invoke the Lambda function
    response = lambda_client.invoke(
        FunctionName=function_name,
        InvocationType="RequestResponse",
        Payload=json.dumps(s3_event),
    )

    # Parse and return the response
    payload = json.loads(response["Payload"].read().decode())
    print(f"Lambda response: {json.dumps(payload, indent=2)}")
    return payload


def check_lambda_logs(function_name, minutes=5):
    """Check CloudWatch logs for the Lambda function"""
    logs = boto3.client("logs", region_name=REGION)

    # Get log group name
    log_group_name = f"/aws/lambda/{function_name}"

    # Calculate start time (minutes ago)
    start_time = int((time.time() - (minutes * 60)) * 1000)

    try:
        # Get log streams
        response = logs.describe_log_streams(
            logGroupName=log_group_name,
            orderBy="LastEventTime",
            descending=True,
            limit=5,
        )

        if not response.get("logStreams"):
            print(f"No log streams found for {log_group_name}")
            return

        # Get the most recent log stream
        log_stream_name = response["logStreams"][0]["logStreamName"]

        # Get log events
        log_events = logs.get_log_events(
            logGroupName=log_group_name,
            logStreamName=log_stream_name,
            startTime=start_time,
            limit=100,
        )

        print(f"\n--- Lambda Logs ({function_name}) ---")
        for event in log_events["events"]:
            print(event["message"])

    except Exception as e:
        print(f"Error retrieving logs: {str(e)}")


def check_eventbridge_events(source, detail_type, minutes=5):
    """Check EventBridge events that were recently sent"""
    events = boto3.client("events", region_name=REGION)
    cloudtrail = boto3.client("cloudtrail", region_name=REGION)

    # Calculate start time (minutes ago)
    start_time = datetime.fromtimestamp(time.time() - (minutes * 60))
    end_time = datetime.now()  # Add end time to fix the time range issue

    try:
        # Look up events in CloudTrail
        response = cloudtrail.lookup_events(
            LookupAttributes=[
                {
                    "AttributeKey": "EventSource",
                    "AttributeValue": "events.amazonaws.com",
                }
            ],
            StartTime=start_time,
            EndTime=end_time,  # Add end time parameter
            MaxResults=10,
        )

        print(f"\n--- Recent EventBridge Events ---")
        for event in response.get("Events", []):
            event_data = json.loads(event.get("CloudTrailEvent", "{}"))
            if "PutEvents" in event_data.get("eventName", ""):
                print(f"Event: {event_data.get('eventName')}")
                print(f"Time: {event_data.get('eventTime')}")
                print(
                    f"Request: {json.dumps(event_data.get('requestParameters', {}), indent=2)}"
                )
                print("---")

    except Exception as e:
        print(f"Error checking EventBridge events: {str(e)}")


def check_ecs_tasks(cluster_name, minutes=10):
    """Check ECS tasks that were recently run"""
    ecs = boto3.client("ecs", region_name=REGION)

    # List tasks with stopped status as well
    try:
        # First check running tasks
        running_response = ecs.list_tasks(cluster=cluster_name, maxResults=10)

        # Then check recently stopped tasks
        stopped_response = ecs.list_tasks(
            cluster=cluster_name, maxResults=10, desiredStatus="STOPPED"
        )

        task_arns = running_response.get("taskArns", []) + stopped_response.get(
            "taskArns", []
        )

        if not task_arns:
            print(f"No tasks found in cluster {cluster_name}")

            # List all clusters to verify the cluster exists
            clusters = ecs.list_clusters()
            print(f"Available clusters: {clusters.get('clusterArns', [])}")

            return

        # Describe tasks
        tasks = ecs.describe_tasks(cluster=cluster_name, tasks=task_arns)

        print(f"\n--- ECS Tasks ({cluster_name}) ---")
        for task in tasks["tasks"]:
            # Get task creation time
            created_at = task.get("createdAt")
            if created_at:
                # Check if task was created within the last X minutes
                task_age_minutes = (time.time() - created_at.timestamp()) / 60
                if task_age_minutes <= minutes:
                    print(f"Task ARN: {task['taskArn']}")
                    print(f"Status: {task['lastStatus']}")
                    print(f"Created: {task['createdAt']}")

                    # Show task stopped reason if available
                    if task.get("stoppedReason"):
                        print(f"Stopped reason: {task['stoppedReason']}")

                    # Get container details
                    for container in task.get("containers", []):
                        print(f"Container: {container['name']}")
                        print(f"Container Status: {container.get('lastStatus')}")

                        # Show container exit code and reason if available
                        if container.get("exitCode") is not None:
                            print(f"Exit code: {container.get('exitCode')}")
                        if container.get("reason"):
                            print(f"Reason: {container.get('reason')}")

                    # Check CloudWatch logs for this task
                    check_task_logs(cluster_name, task["taskArn"])

    except Exception as e:
        print(f"Error checking ECS tasks: {str(e)}")
        import traceback

        traceback.print_exc()


def check_task_logs(cluster_name, task_arn):
    """Check CloudWatch logs for a specific ECS task"""
    logs = boto3.client("logs", region_name=REGION)
    ecs = boto3.client("ecs", region_name=REGION)

    # Extract task ID from ARN
    task_id = task_arn.split("/")[-1]

    try:
        # Get task details
        task_details = ecs.describe_tasks(cluster=cluster_name, tasks=[task_arn])

        if not task_details.get("tasks"):
            return

        # Get container details
        for container in task_details["tasks"][0].get("containers", []):
            # Log group is typically /aws/ecs/{task-name}
            log_group_name = "/aws/ecs/tccw-knowledge-doc-agent-container"

            # Log stream typically includes task ID
            log_stream_prefix = f"ecs/{container['name']}/{task_id}"

            try:
                # Find matching log streams
                streams = logs.describe_log_streams(
                    logGroupName=log_group_name,
                    logStreamNamePrefix=log_stream_prefix,
                    limit=1,
                )

                if not streams.get("logStreams"):
                    print(f"No log streams found for container {container['name']}")
                    continue

                # Get log events
                log_events = logs.get_log_events(
                    logGroupName=log_group_name,
                    logStreamName=streams["logStreams"][0]["logStreamName"],
                    limit=50,
                )

                print(f"\n--- Container Logs ({container['name']}) ---")
                for event in log_events["events"]:
                    print(event["message"])

            except Exception as e:
                print(f"Error retrieving container logs: {str(e)}")

    except Exception as e:
        print(f"Error retrieving task details: {str(e)}")


def main():
    # Configuration
    lambda_function_name = "tccw-knowledge-doc-agent"
    ecs_cluster_name = "tccw-knowledge-doc-agent-cluster"
    event_source = "tccw.knowledge.doc.agent"
    event_detail_type = "S3ObjectCreated"

    # Choose ONE of the following approaches:

    # APPROACH 1: Upload test files to S3 and let the natural event flow trigger the pipeline
    test_dir_path, file_keys = upload_test_files()
    print(f"Test directory created: {test_dir_path}")
    print(f"Test files uploaded: {', '.join(file_keys)}")

    # Wait for S3 event to propagate
    print("Waiting for S3 events to propagate (5 seconds)...")
    time.sleep(5)

    # Comment out the direct Lambda invocation
    # lambda_response = invoke_lambda_directly(lambda_function_name, test_dir_path)

    # OR APPROACH 2: Directly invoke Lambda with simulated event (without uploading real files)
    # test_dir_path = f"{PREFIX}test_{uuid.uuid4().hex[:8]}/"
    # print(f"Test directory created: {test_dir_path}")
    # lambda_response = invoke_lambda_directly(lambda_function_name, test_dir_path)

    # Check Lambda logs
    print("Checking Lambda logs...")
    check_lambda_logs(lambda_function_name)

    # Check EventBridge events
    print("Checking EventBridge events...")
    check_eventbridge_events(event_source, event_detail_type)

    # Wait longer for ECS task to start
    print("Waiting for ECS task to start (60 seconds)...")
    time.sleep(60)  # Increased wait time

    # Check ECS tasks
    print("Checking ECS tasks...")
    check_ecs_tasks(ecs_cluster_name)

    print("\nTest complete! Check the console for more details if needed.")
    print(f"Test directory: {test_dir_path}")


if __name__ == "__main__":
    main()
