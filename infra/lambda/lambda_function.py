from tccw_knowledge_doc_agent.crew import TccwKnowledgeDocAgent
import json
import os


def lambda_handler(event, context):
    """
    AWS Lambda handler function triggered by S3 bucket events
    """
    try:
        # Extract bucket and key information from the event
        bucket = event["Records"][0]["s3"]["bucket"]["name"]
        key = event["Records"][0]["s3"]["object"]["key"]

        print(f"Processing file {key} from bucket {bucket}")

        # Initialize the TccwKnowledgeDocAgent
        agent = TccwKnowledgeDocAgent()

        # Process with a default topic or extract from filename
        topic = "AI LLMs"  # Default topic
        if key.endswith(".txt"):
            # You could extract topic from filename or content if needed
            topic = key.split("/")[-1].replace(".txt", "").replace("_", " ")

        # Run the agent with the topic
        result = agent.crew().kickoff(inputs={"topic": topic})

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Document processing completed successfully",
                    "bucket": bucket,
                    "key": key,
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
