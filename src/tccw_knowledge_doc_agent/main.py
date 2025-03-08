#!/usr/bin/env python
from tccw_knowledge_doc_agent.crew import TccwKnowledgeDocAgent
from typing import Dict, Any
import warnings
import asyncio
import boto3
import sys
import os
from crewai.knowledge.source.string_knowledge_source import StringKnowledgeSource

warnings.filterwarnings("ignore", category=SyntaxWarning, module="pysbd")

# Environment variables configuration
ENVIRONMENT = {
    "S3_EVENT_BUCKET": os.environ.get("S3_EVENT_BUCKET", ""),
    "S3_EVENT_KEY": os.environ.get("S3_EVENT_KEY", ""),
}

# Initialize S3 client
s3_client = boto3.client("s3")


def get_env(key: str) -> Any:
    """Get environment variable value"""
    return ENVIRONMENT.get(key)


def get_and_merge_objects(bucket: str, prefix: str) -> str:
    """
    Fetches all objects from the given prefix in the bucket and merges their content.
    """
    print(f"Fetching all objects from bucket {bucket} with prefix {prefix}")

    if not prefix.endswith("/"):
        prefix = prefix + "/"

    response = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)

    if "Contents" not in response:
        print(f"No objects found in {bucket}/{prefix}")
        return ""

    object_keys = [obj["Key"] for obj in response["Contents"]]
    print(f"Found {len(object_keys)} objects: {object_keys}")

    merged_content = ""

    for key in object_keys:
        if key.endswith("/"):
            continue

        print(f"Getting content of {key}")
        obj = s3_client.get_object(Bucket=bucket, Key=key)
        content = obj["Body"].read().decode("utf-8")

        if merged_content:
            merged_content += "\n\n--- New File ---\n\n"

        merged_content += f"File: {key}\n{content}"

    print(f"Total merged content size: {len(merged_content)} characters")
    return merged_content


def get_processed_content() -> Dict[str, Any]:
    """
    Process document from S3 and return content and topic
    """
    bucket = get_env("S3_EVENT_BUCKET")
    key = get_env("S3_EVENT_KEY")

    if not bucket or not key:
        print(
            "Error: S3_EVENT_BUCKET and S3_EVENT_KEY environment variables must be set"
        )
        return {"topic": "AI LLMs", "content": ""}

    path_parts = key.split("/")

    if len(path_parts) <= 1:
        container_prefix = ""
    else:
        container_prefix = "/".join(path_parts[:-1]) + "/"

    merged_content = get_and_merge_objects(bucket, container_prefix)

    topic = "Default Topic"

    if container_prefix:
        topic = container_prefix.rstrip("/").split("/")[-1].replace("_", " ").title()

    return {"topic": topic, "content": merged_content}


def run():
    """
    Run the crew with content from S3 if available, otherwise use default
    """
    try:
        result = asyncio.run(
            TccwKnowledgeDocAgent()
            .crew()
            .kickoff_async(
                inputs={"transcript": TccwKnowledgeDocAgent.get_processed_content()}
            )
        )
        return result
    except Exception as e:
        raise Exception(f"An error occurred while running the crew: {e}")


def train():
    """
    Train the crew for a given number of iterations.
    """
    try:
        TccwKnowledgeDocAgent().crew().train(
            n_iterations=int(sys.argv[1]),
            filename=sys.argv[2],
            inputs={"transcript": TccwKnowledgeDocAgent.get_processed_content()},
        )
    except Exception as e:
        raise Exception(f"An error occurred while training the crew: {e}")


def replay():
    """
    Replay the crew execution from a specific task.
    """
    try:
        TccwKnowledgeDocAgent().crew().replay(task_id=sys.argv[1])
    except Exception as e:
        raise Exception(f"An error occurred while replaying the crew: {e}")


def test():
    """
    Test the crew execution and returns the results.
    """
    try:
        TccwKnowledgeDocAgent().crew().test(
            n_iterations=int(sys.argv[1]),
            openai_model_name=sys.argv[2],
            inputs={"transcript": TccwKnowledgeDocAgent.get_processed_content()},
        )
    except Exception as e:
        raise Exception(f"An error occurred while testing the crew: {e}")


if __name__ == "__main__":
    run()
