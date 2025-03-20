#!/usr/bin/env python
from tccw_knowledge_doc_agent.crew import TccwKnowledgeDocAgent, get_processed_content
import warnings
import asyncio
import sys

warnings.filterwarnings("ignore", category=SyntaxWarning, module="pysbd")
processed_data = get_processed_content()


def run():
    """
    Run the crew with content from S3 if available, otherwise use default
    """
    try:
        result = asyncio.run(
            TccwKnowledgeDocAgent()
            .crew()
            .kickoff_async(
                inputs={
                    "notes_subject": processed_data["topic"],
                    "transcription": processed_data["content"],
                }
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
            inputs={
                "notes_subject": processed_data["topic"],
                "transcription": processed_data["content"],
            },
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
            inputs={
                "notes_subject": processed_data["topic"],
                "transcription": processed_data["content"],
            },
        )
    except Exception as e:
        raise Exception(f"An error occurred while testing the crew: {e}")


if __name__ == "__main__":
    run()
