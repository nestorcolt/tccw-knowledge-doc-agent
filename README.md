# TCCW Knowledge Document Agent

A sophisticated AI-powered document analysis and knowledge extraction system now featuring Confluence integration for automated page creation. This system processes documents stored in S3, analyzes their content, and generates comprehensive documentation using a team of specialized AI agents.

## Architecture

```mermaid
graph TD
    subgraph AWS
        S3[S3 Bucket] --> |Document Storage| ECR[ECR Repository]
        SM[Secrets Manager] --> |SSH Keys| ECR
    end

    subgraph DocAgent[TCCW Knowledge Doc Agent]
        MA[Manager Agent] --> AN[Analyzer Agent]
        MA --> DG[Doc Generation Agent]
        MA --> CA[Confluence Agent]
        AN --> DG
        KS[Knowledge Source] --> AN
    end

    subgraph Tools
        FW[File Writer Tool]
        CT[Composio Tools]
    end

    S3 --> |Input Documents| DocAgent
    DG --> |Generated Docs| Output[Output Documents]
    CA --> |Page Creation| Output
    Tools --> DocAgent

```

## Features

- **Multi-Agent System**: Specialized agents for document analysis:
  - Manager Agent: Orchestrates the workflow
  - Analyzer Agent: Processes document content
  - Doc Generation Agent: Creates documentation
  - **Confluence Agent**: Automates Confluence page creation
- **AWS Integration**: 
  - S3 bucket storage
  - ECR for container deployment
  - Secrets Manager for secure credentials
- **Containerized Deployment**: Docker-based deployment for scalability and consistency
- **Flexible Tool System**: Extensible tool architecture for custom functionality

## Prerequisites

- Python >=3.11, <3.13
- Docker
- AWS CLI v2
- Access to AWS services (S3, ECR, Secrets Manager)

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd tccw-knowledge-doc-agent
```

2. Install dependencies (recommended):
```bash
pip install --editable .
```

3. Set up environment variables:
   - Create a `.env` file in your home directory (e.g., ~/.env) based on the provided template.

## Configuration

1. AWS Credentials:
   - Ensure AWS credentials are properly configured
   - Set up necessary IAM roles and permissions

2. Environment Variables:
   - Create a `.env` file based on the provided template
   - Configure all required AWS service endpoints

## Usage

### Local Development

1. Run the agent locally:
```bash
python -m tccw_knowledge_doc_agent.main
```

2. Training mode:
```bash
python -m tccw_knowledge_doc_agent.main train <iterations> <filename>
```

3. Test mode:
```bash
python -m tccw_knowledge_doc_agent.main test <iterations> <model_name>
```

### Docker Deployment

1. Build and push to ECR:
```bash
./docker.sh <task-name> <tag> <ecr-url> <ecr-full-url> <region> true
```

2. Run container:
```bash
docker run -e AWS_ACCESS_KEY_ID=<key> \
           -e AWS_SECRET_ACCESS_KEY=<secret> \
           -e S3_EVENT_BUCKET=<bucket> \
           -e S3_EVENT_KEY=<key> \
           <ecr-full-url>
```

## Development

### Project Structure
```
tccw-knowledge-doc-agent/
├── src/
│   └── tccw_knowledge_doc_agent/
│       ├── crew.py          # Core agent implementation
│       ├── main.py          # Entry point
│       └── tools/           # Custom tools
├── knowledge/              # Knowledge base
└── docker/                # Docker configuration
```

### Adding Custom Tools

1. Create a new tool in `src/tccw_knowledge_doc_agent/tools/`
2. Inherit from `BaseTool`
3. Define input schema and implementation
4. Register in the crew configuration

## CI/CD

- GitHub Actions workflow for automated builds
- Automated ECR push on main branch updates
- Build validation on pull requests

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

[License Type] - See LICENSE file for details

## Author

Nestor Colt (nestor.colt@gmail.com)

## Support

For support and questions:
- Create an issue in the repository
- Contact the development team
- Refer to the documentation
