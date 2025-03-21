from crewai_tools import FileWriterTool, FileReadTool
from cognition_core.crew import CognitionCoreCrewBase
from cognition_core.agent import CognitionAgent
from cognition_core.crew import CognitionCrew
from cognition_core.task import CognitionTask
from crewai.project import agent, crew, task
from composio_crewai import ComposioToolSet
from typing import Dict, Any
import boto3
import os


# Environment variables configuration
ENVIRONMENT = {
    "S3_BUCKET_NAME": os.environ.get("S3_BUCKET_NAME", ""),
    "S3_OBJECT_KEY": os.environ.get("S3_OBJECT_KEY", ""),
}

# Initialize S3 client
s3_client = boto3.client("s3")
file_writer_tool = FileWriterTool(
    name="file_writer",
    description="Write content to a markdown file",
)
file_read_tool = FileReadTool(
    name="file_reader",
    description="Read content from a markdown file",
)

composio_toolset = ComposioToolSet(
    api_key=os.getenv("COMPOSIO_API_KEY"),
    entity_id=os.getenv("COMPOSIO_CONFLUENCE_ENTITY_ID"),
)
composio_tools = composio_toolset.get_tools(
    actions=["CONFLUENCE_GET_CHILD_PAGES", "CONFLUENCE_CREATE_PAGE"]
)

composio_tools.append(file_read_tool)


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
    try:
        bucket = get_env("S3_BUCKET_NAME")
        key = get_env("S3_OBJECT_KEY")

        if not bucket or not key:
            print(
                "Error: S3_BUCKET_NAME and S3_OBJECT_KEY environment variables must be set"
            )
            return {"topic": "AI LLMs", "content": "No content available"}

        path_parts = key.split("/")

        if len(path_parts) <= 1:
            container_prefix = ""
        else:
            container_prefix = "/".join(path_parts[:-1]) + "/"

        merged_content = get_and_merge_objects(bucket, container_prefix)
        return {
            "topic": path_parts[-1],
            "content": merged_content or "No content available",
        }

    except Exception as e:
        print(f"Error in get_processed_content: {e}")
        return {"topic": "Error", "content": "Error processing content"}


@CognitionCoreCrewBase
class TccwKnowledgeDocAgent:
    """Base Cognition implementation - Virtual Interface"""

    def __init__(self) -> None:
        super().__init__()

    @agent
    def document_generator_agent(self) -> CognitionAgent:
        return self.get_cognition_agent(
            config=self.agents_config["document_generator_agent"],
            tools=[file_writer_tool],
        )

    @task
    def document_generation_task(self) -> CognitionTask:
        task_config = self.tasks_config["document_generation_task"]
        return CognitionTask(
            name="document_generation_task",
            tools=[file_writer_tool],
            config=task_config,
            tool_names=self.list_tools(),
            tool_service=self.tool_service,
        )

    @agent
    def confluence_agent(self) -> CognitionAgent:
        return self.get_cognition_agent(
            config=self.agents_config["confluence_agent"], tools=composio_tools
        )

    @task
    def confluence_publishing_task(self) -> CognitionTask:
        """Input analysis task"""
        task_config = self.tasks_config["confluence_publishing_task"]
        return CognitionTask(
            name="confluence_publishing_task",
            config=task_config,
            tools=composio_tools,
            tool_names=self.list_tools(),
            tool_service=self.tool_service,
        )

    @crew
    def crew(self) -> CognitionCrew:
        return CognitionCrew(
            agents=self.agents,
            tasks=self.tasks,
            verbose=True,
            embedder=self.memory_service.embedder,
            tool_service=self.tool_service,
            short_term_memory=self.memory_service.get_short_term_memory(),
            entity_memory=self.memory_service.get_entity_memory(),
            long_term_memory=self.memory_service.get_long_term_memory(),
        )
