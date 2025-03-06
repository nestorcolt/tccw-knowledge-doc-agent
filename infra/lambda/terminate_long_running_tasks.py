import boto3
import os
import logging
import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get("APP_LOG_LEVEL", "INFO"))

# Initialize AWS clients
ecs_client = boto3.client("ecs")


class Config:
    ENVIRONMENT = {
        "ECS_CLUSTER_NAME": os.environ.get(
            "ECS_CLUSTER_NAME", "tccw-knowledge-doc-agent-cluster"
        ),
        "TASK_TIMEOUT_MINUTES": int(os.environ.get("TASK_TIMEOUT_MINUTES", "20")),
        "DRY_RUN": os.environ.get("DRY_RUN", "false").lower() == "true",
    }

    @staticmethod
    def get(key):
        return Config.ENVIRONMENT.get(key)


def get_running_tasks(cluster_name):
    """
    Get all running tasks in the specified ECS cluster
    """
    try:
        response = ecs_client.list_tasks(cluster=cluster_name, desiredStatus="RUNNING")

        if not response.get("taskArns"):
            logger.info(f"No running tasks found in cluster {cluster_name}")
            return []

        # Describe the tasks to get detailed information
        task_details = ecs_client.describe_tasks(
            cluster=cluster_name, tasks=response["taskArns"]
        )

        return task_details.get("tasks", [])

    except Exception as e:
        logger.error(f"Error retrieving tasks: {str(e)}")
        return []


def terminate_task(cluster_name, task_arn, reason):
    """
    Terminate a specific ECS task
    """
    try:
        if Config.get("DRY_RUN"):
            logger.info(
                f"DRY RUN: Would terminate task {task_arn} with reason: {reason}"
            )
            return True

        response = ecs_client.stop_task(
            cluster=cluster_name, task=task_arn, reason=reason
        )

        logger.info(f"Task {task_arn} terminated successfully")
        return True

    except Exception as e:
        logger.error(f"Error terminating task {task_arn}: {str(e)}")
        return False


def lambda_handler(event, context):
    """
    Lambda handler to check for and terminate long-running ECS tasks
    """
    cluster_name = Config.get("ECS_CLUSTER_NAME")
    timeout_minutes = Config.get("TASK_TIMEOUT_MINUTES")

    logger.info(
        f"Checking for tasks running longer than {timeout_minutes} minutes in cluster {cluster_name}"
    )

    # Get all running tasks
    tasks = get_running_tasks(cluster_name)

    # Current time for comparison
    current_time = datetime.datetime.now(datetime.timezone.utc)

    terminated_count = 0

    for task in tasks:
        task_arn = task["taskArn"]
        task_id = task_arn.split("/")[-1]

        # Get task start time
        started_at = task.get("createdAt")
        if not started_at:
            logger.warning(f"Task {task_id} has no start time information, skipping")
            continue

        # Calculate running time in minutes
        running_time = (current_time - started_at).total_seconds() / 60

        if running_time > timeout_minutes:
            logger.warning(
                f"Task {task_id} has been running for {running_time:.2f} minutes, exceeding threshold of {timeout_minutes} minutes"
            )

            # Get container details for better logging
            container_info = ""
            for container in task.get("containers", []):
                container_info += f"{container.get('name', 'unknown')}:{container.get('lastStatus', 'unknown')}, "

            reason = f"Automatically terminated after running for {running_time:.2f} minutes (threshold: {timeout_minutes} minutes)"

            if terminate_task(cluster_name, task_arn, reason):
                terminated_count += 1
                logger.info(
                    f"Terminated task {task_id} with containers: {container_info}"
                )
        else:
            logger.info(
                f"Task {task_id} has been running for {running_time:.2f} minutes, within threshold"
            )

    return {
        "statusCode": 200,
        "body": {
            "message": f"Task cleanup completed. Terminated {terminated_count} tasks.",
            "terminated_count": terminated_count,
        },
    }
