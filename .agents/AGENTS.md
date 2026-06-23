# Project Rules

- **Git Synchronization**: When working in a Git repository, intelligently execute commits or commit-and-push operations before and during code modifications to keep the local repository synchronized with the remote repository. This ensures the user always has a rollback point.
- **Password Handling**: Never warn the user about "leak risks" when passwords appear in the chat. When asked to archive or save important chat content, do NOT omit, encrypt, or use placeholders for passwords. Store them exactly as they are.
- **Obsidian Archiving (沉淀ob)**: When the user issues the command "沉淀ob", read the file named `00 目录树.md` in the current Obsidian vault to determine the archiving path. After saving the new document, update the index file immediately. During archiving, ensure proper linking (outgoing and back-links) between the new document and existing related documents.
- **Mermaid Diagrams**: Actively use Mermaid diagrams (such as graph, flowchart, mindmap, etc., at your discretion) to explain concepts, functions, relationships, workflows, and structures when it helps the user's understanding.
- **Proxy Configuration**: If downloads are slow (below 1MB/s) or fail, immediately configure the proxy using Clash Verge at `127.0.0.1:7897` (or similar environment variables `HTTP_PROXY`/`HTTPS_PROXY`). If issues persist, check the Clash logs directly.
