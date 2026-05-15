# VS Code extensions

Install these from the VS Code Marketplace. The course assumes you have them but does not strictly require them.

| Extension | Publisher | Why install |
|-----------|-----------|-------------|
| **PostgreSQL** | Microsoft (`ms-ossdata.vscode-postgresql`) | Official Microsoft extension. Browse schemas/tables, run queries against a connection, includes a chat assistant for SQL authoring. Preferred over older third-party Postgres extensions because it is actively maintained. |
| **SQLTools** | Matheus Teixeira (`mtxr.sqltools`) | Lightweight in-editor query runner with bookmarks and history. Pairs with the driver below for Postgres connections. |
| **SQLTools PostgreSQL/Cockroach Driver** | Matheus Teixeira (`mtxr.sqltools-driver-pg`) | The Postgres driver SQLTools needs. Configures connection from `vscode/settings.example.json`. |
| **Jupyter** | Microsoft (`ms-toolsai.jupyter`) | Required for the `.ipynb` labs in modules 00, 10, 11, 12. |
| **Python** | Microsoft (`ms-python.python`) | Interpreter selection and language services for the Jupyter labs. |
| **Even Better TOML** | tamasfe (`tamasfe.even-better-toml`) | Syntax + validation for `pyproject.toml` and alembic config. Optional. |
| **DotENV** | mikestead (`mikestead.dotenv`) | Syntax highlighting for `.env` and `.env.example`. Optional. |
| **Mermaid Preview** | Vyacheslav Pukhanov (`bierner.markdown-mermaid`) | Renders the Mermaid diagrams in module READMEs inside VS Code's markdown preview. Optional but pleasant. |

## Workspace settings

Copy `vscode/settings.example.json` to `.vscode/settings.json` in this repo (the latter is gitignored). It contains a SQLTools connection stub pre-wired for the course.
