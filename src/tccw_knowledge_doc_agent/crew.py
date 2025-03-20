from composio_crewai import ComposioToolSet, App, Action
from cognition_core.crew import CognitionCoreCrewBase
from cognition_core.base import ComponentManager
from cognition_core.llm import init_portkey_llm
from cognition_core.agent import CognitionAgent
from cognition_core.task import CognitionTask
from cognition_core.crew import CognitionCrew
from crewai.project import agent, crew, task
from cognition_core.api import CoreAPIService
from crewai_tools import FileWriterTool
from typing import Dict, Any
from crewai import Process
import asyncio
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
    description="Write content to a file",
)

composio_toolset = ComposioToolSet(
    api_key=os.getenv("COMPOSIO_API_KEY"),
    entity_id=os.getenv("COMPOSIO_CONFLUENCE_ENTITY_ID"),
)
composio_tools = composio_toolset.get_tools(
    actions=["CONFLUENCE_CREATE_PAGE", "CONFLUENCE_GET_CHILD_PAGES"]
)

print(os.getenv("COMPOSIO_API_KEY"))
print(os.getenv("COMPOSIO_CONFLUENCE_ENTITY_ID"))


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

        topic = "Default Topic"

        if container_prefix:
            topic = (
                container_prefix.rstrip("/").split("/")[-1].replace("_", " ").title()
            )

        return {"topic": topic, "content": merged_content or "No content available"}
    except Exception as e:
        print(f"Error in get_processed_content: {e}")
        return {"topic": "Error", "content": "Error processing content"}


@CognitionCoreCrewBase
class TccwKnowledgeDocAgent(ComponentManager):
    """Base Cognition implementation - Virtual Interface"""

    def __init__(self):
        # Initialize FastAPI
        self.api = CoreAPIService()
        self.app = self.api.get_app()

        # Initialize empty components first
        self.available_components = {"agents": [], "tasks": []}

        # Call parent so CrewBase processes @agent/@task decorators
        super().__init__()
        # Try deferring the update until an event loop is available
        try:
            loop = asyncio.get_running_loop()
            loop.call_soon(self._update_components)
        except RuntimeError:
            # No running loop - update components immediately
            self._update_components()

    # Now these methods implement the abstract interface
    def _update_components(self) -> None:
        """Implements ComponentManager.update_components"""
        agents = getattr(self, "agents", [])
        tasks = getattr(self, "tasks", [])
        self.available_components = {
            "agents": [a for a in agents if a.is_available],
            "tasks": [t for t in tasks if t.is_available],
        }

    def activate_component(self, component_type: str, name: str) -> bool:
        """Implements ComponentManager.activate_component"""
        if component_type in self.available_components:
            for component in self.available_components[component_type]:
                if component.name == name:
                    component.enabled = True
                    return True
        return False

    def deactivate_component(self, component_type: str, name: str) -> bool:
        """Implements ComponentManager.deactivate_component"""
        if component_type in self.available_components:
            for component in self.available_components[component_type]:
                if component.name == name:
                    component.enabled = False
                    return True
        return False

    def get_active_workflow(self) -> dict:
        """Implements ComponentManager.get_active_workflow"""
        return {
            "agents": [a.name for a in self.available_components["agents"]],
            "tasks": [t.name for t in self.available_components["tasks"]],
        }

    @agent
    def analyzer(self) -> CognitionAgent:
        """Analysis specialist agent"""
        # llm = init_portkey_llm(
        #     model=self.agents_config["analyzer"]["llm"],
        #     portkey_config=self.portkey_config,
        # )
        return self.get_cognition_agent(
            config=self.agents_config["analyzer"],
            # llm=llm,
        )

    @task
    def analysis_task(self) -> CognitionTask:
        """Input analysis task"""
        task_config = self.tasks_config["analysis_task"]
        return CognitionTask(
            name="analysis_task",
            config=task_config,
            tool_names=self.list_tools(),
            tool_service=self.tool_service,
        )

    @agent
    def doc_generation_agent(self) -> CognitionAgent:
        """Analysis specialist agent"""
        # llm = init_portkey_llm(
        #     model=self.agents_config["doc_generation_agent"]["llm"],
        #     portkey_config=self.portkey_config,
        # )
        return self.get_cognition_agent(
            config=self.agents_config["doc_generation_agent"],
            tools=[file_writer_tool],
            # llm=llm,
        )

    @task
    def doc_generation_task(self) -> CognitionTask:
        """Input analysis task"""
        task_config = self.tasks_config["doc_generation_task"]
        return CognitionTask(
            name="doc_generation_task",
            tools=[file_writer_tool],
            config=task_config,
            tool_names=self.list_tools(),
            tool_service=self.tool_service,
        )

    @agent
    def confluence_agent(self) -> CognitionAgent:
        """Analysis specialist agent"""
        # llm = init_portkey_llm(
        #     model=self.agents_config["doc_generation_agent"]["llm"],
        #     portkey_config=self.portkey_config,
        # )
        return self.get_cognition_agent(
            config=self.agents_config["confluence_agent"],
            tools=composio_tools,
            # llm=llm,
        )

    @task
    def confluence_task(self) -> CognitionTask:
        """Input analysis task"""
        task_config = self.tasks_config["confluence_task"]
        return CognitionTask(
            name="confluence_task",
            config=task_config,
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
