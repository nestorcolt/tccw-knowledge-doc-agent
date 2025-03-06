import boto3
import uuid
import time
import json

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


def upload_test_file():
    """Upload a test file to S3 to trigger the pipeline"""
    s3 = boto3.client("s3", region_name=REGION)

    # Create a unique filename
    test_file_key = f"{PREFIX}test/document_{uuid.uuid4()}.txt"

    print(f"Uploading test file to s3://{SOURCE_BUCKET}/{test_file_key}")

    # Upload the file
    s3.put_object(
        Bucket=SOURCE_BUCKET,
        Key=test_file_key,
        Body=TEST_CONTENT,
        ContentType="text/markdown",
    )

    return test_file_key


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


def check_ecs_tasks(cluster_name, minutes=10):
    """Check ECS tasks that were recently run"""
    ecs = boto3.client("ecs", region_name=REGION)

    # List tasks
    try:
        response = ecs.list_tasks(cluster=cluster_name, maxResults=10)

        if not response.get("taskArns"):
            print(f"No tasks found in cluster {cluster_name}")
            return

        # Describe tasks
        tasks = ecs.describe_tasks(cluster=cluster_name, tasks=response["taskArns"])

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

                    # Get container details
                    for container in task.get("containers", []):
                        print(f"Container: {container['name']}")
                        print(f"Container Status: {container.get('lastStatus')}")

                    # Check CloudWatch logs for this task
                    check_task_logs(cluster_name, task["taskArn"])

    except Exception as e:
        print(f"Error checking ECS tasks: {str(e)}")


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
            log_group_name = f"/aws/ecs/tccw-knowledge-doc-agent-task"

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


def check_eventbridge_events(source, detail_type, minutes=5):
    """Check EventBridge events that were recently sent"""
    events = boto3.client("events", region_name=REGION)
    cloudtrail = boto3.client("cloudtrail", region_name=REGION)

    # Calculate start time (minutes ago)
    start_time = time.time() - (minutes * 60)

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


def main():
    # Configuration
    lambda_function_name = "tccw-knowledge-doc-agent"
    ecs_cluster_name = "tccw-knowledge-doc-agent-cluster"
    event_source = "tccw.knowledge.doc.agent"
    event_detail_type = "S3ObjectCreated"

    # Upload test file
    test_file_key = upload_test_file()
    print(f"Test file uploaded: {test_file_key}")

    # Wait for Lambda to process
    print("Waiting for Lambda to process (10 seconds)...")
    time.sleep(10)

    # Check Lambda logs
    check_lambda_logs(lambda_function_name)

    # Check EventBridge events
    check_eventbridge_events(event_source, event_detail_type)

    # Wait for ECS task to start
    print("Waiting for ECS task to start (30 seconds)...")
    time.sleep(30)

    # Check ECS tasks
    check_ecs_tasks(ecs_cluster_name)

    print("\nTest complete! Check the console for more details if needed.")


if __name__ == "__main__":
    main()
