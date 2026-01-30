# Custom Tools & Agents

In-depth patterns for defining tools with type-safe schemas, validation, and creating specialized agent personas.

## Tool Definition Patterns

### Pattern 1: Type-Safe Tools (Recommended)

#### TypeScript with Zod

```typescript
import { z } from "zod";
import { defineTool } from "@github/copilot-sdk";

const getUserTool = defineTool("get_user", {
    description: "Fetch user information by ID",
    parameters: z.object({
        userId: z.string()
            .describe("Unique user identifier")
            .refine(id => /^\d+$/.test(id), "User ID must be numeric"),
        includeDetails: z.boolean()
            .optional()
            .describe("Include full profile details (default: false)")
    }),
    handler: async ({ userId, includeDetails }) => {
        try {
            const user = await fetchUserFromDB(userId);
            if (!user) {
                return {
                    textResultForLlm: `User ${userId} not found`,
                    resultType: "failure",
                    error: "User not found"
                };
            }
            return {
                textResultForLlm: `User: ${user.name} (${user.email})`,
                resultType: "success",
                toolTelemetry: {
                    userId,
                    foundAt: new Date().toISOString(),
                    detailsIncluded: includeDetails
                }
            };
        } catch (error) {
            return {
                textResultForLlm: `Failed to fetch user: ${error.message}`,
                resultType: "failure",
                error: error.message
            };
        }
    }
});

const session = await client.createSession({
    tools: [getUserTool]
});
```

#### Python with Pydantic

```python
from pydantic import BaseModel, Field, field_validator
from copilot import define_tool
from typing import Optional

class GetUserParams(BaseModel):
    user_id: str = Field(description="Unique user identifier")
    include_details: Optional[bool] = Field(
        default=False, 
        description="Include full profile details"
    )
    
    @field_validator("user_id")
    def validate_user_id(cls, v):
        if not v.isdigit():
            raise ValueError("User ID must be numeric")
        return v

@define_tool(description="Fetch user information by ID")
async def get_user(params: GetUserParams) -> dict:
    try:
        user = await fetch_user_from_db(params.user_id)
        if not user:
            return {
                "textResultForLlm": f"User {params.user_id} not found",
                "resultType": "failure",
                "error": "User not found"
            }
        return {
            "textResultForLlm": f"User: {user['name']} ({user['email']})",
            "resultType": "success",
            "toolTelemetry": {
                "userId": params.user_id,
                "detailsIncluded": params.include_details
            }
        }
    except Exception as error:
        return {
            "textResultForLlm": f"Failed to fetch user: {str(error)}",
            "resultType": "failure",
            "error": str(error)
        }

session = await client.create_session({
    "tools": [get_user]
})
```

---

### Pattern 2: Raw Schema Tools (Low-Level)

For complex scenarios where type-safe helpers don't fit:

```typescript
const customTool = {
    name: "process_data",
    description: "Process data with custom logic",
    parameters: {
        type: "object",
        properties: {
            input: {
                type: "string",
                description: "Input data"
            },
            format: {
                type: "string",
                enum: ["json", "csv", "xml"],
                description: "Output format"
            }
        },
        required: ["input", "format"]
    },
    handler: async (args: { input: string; format: string }) => {
        // Custom processing logic
        return {
            textResultForLlm: `Processed ${args.input} in ${args.format} format`,
            resultType: "success"
        };
    }
};

const session = await client.createSession({
    tools: [customTool]
});
```

---

## Tool Result Strategies

### Success Pattern

```typescript
{
    textResultForLlm: "User John Doe created successfully",
    resultType: "success",
    sessionLog: "User record inserted into database with ID 12345",
    toolTelemetry: {
        userId: 12345,
        email: "john@example.com",
        createdAt: "2025-01-30T10:00:00Z"
    }
}
```

### Failure Pattern

```typescript
{
    textResultForLlm: "Failed to create user: Email already exists",
    resultType: "failure",
    error: "DUPLICATE_EMAIL",
    sessionLog: "Email validation failed at insertion attempt",
    toolTelemetry: {
        errorCode: "DUPLICATE_EMAIL",
        email: "john@example.com",
        attemptedAt: "2025-01-30T10:00:00Z"
    }
}
```

### Partial Result Pattern

```typescript
{
    textResultForLlm: "User created but email verification pending",
    resultType: "success",  // Partial success is still "success"
    sessionLog: "User record created. Email verification sent to john@example.com",
    toolTelemetry: {
        userId: 12345,
        emailVerified: false,
        nextAction: "user must click verification link"
    }
}
```

---

## Tool Composition

### Chaining Tools

Combine simple tools into complex workflows:

```typescript
const readFileTool = defineTool("read_file", {
    description: "Read file contents",
    parameters: z.object({
        path: z.string().describe("File path")
    }),
    handler: async ({ path }) => {
        const content = await fs.readFile(path, "utf-8");
        return { textResultForLlm: content, resultType: "success" };
    }
});

const processFileTool = defineTool("process_file", {
    description: "Process file data",
    parameters: z.object({
        data: z.string().describe("Data to process"),
        operation: z.enum(["count", "summarize", "validate"])
    }),
    handler: async ({ data, operation }) => {
        let result;
        if (operation === "count") {
            result = data.split("\n").length;
        }
        return { textResultForLlm: `${operation} result: ${result}`, resultType: "success" };
    }
});

const session = await client.createSession({
    tools: [readFileTool, processFileTool]
});

// Assistant can now: read file -> process data -> return result
```

---

## Custom Agents

### Basic Agent Definition

```typescript
const session = await client.createSession({
    customAgents: [
        {
            name: "code-reviewer",
            displayName: "Code Reviewer",
            description: "Reviews code for quality and security",
            prompt: `You are an expert code reviewer with 10+ years experience.
Your responsibilities:
1. Identify potential bugs and security vulnerabilities
2. Suggest performance improvements
3. Check code style compliance
4. Recommend best practices

Always be constructive and provide actionable feedback.`,
            tools: ["Read", "Grep", "Glob"],
            infer: true  // Can be used for model inference
        }
    ]
});

// Invoke with mention
await session.sendAndWait({
    prompt: "@code-reviewer Please review the authentication module in src/auth.ts"
});
```

### Agent with MCP Servers

```typescript
const session = await client.createSession({
    customAgents: [
        {
            name: "database-engineer",
            displayName: "Database Engineer",
            description: "Specializes in database design and optimization",
            prompt: `You are a database architecture expert.
Focus on:
- Schema optimization
- Query performance
- Data integrity
- Scalability`,
            tools: ["Read", "Write"],
            mcpServers: {
                "postgres": {
                    type: "local",
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-postgres"],
                    tools: "*",
                    env: {
                        "PG_CONNECTION_STRING": process.env.DATABASE_URL
                    }
                }
            }
        }
    ]
});

await session.sendAndWait({
    prompt: "@database-engineer Analyze the current schema and suggest optimizations"
});
```

### Multi-Agent Workflows

```typescript
const session = await client.createSession({
    customAgents: [
        {
            name: "requirements-analyst",
            displayName: "Requirements Analyst",
            description: "Gathers and analyzes requirements",
            prompt: "You are a business analyst. Extract clear, testable requirements.",
            tools: ["Read", "Grep"],
            infer: true
        },
        {
            name: "architect",
            displayName: "Solutions Architect",
            description: "Designs technical solutions",
            prompt: "You are a solutions architect. Design scalable, maintainable systems.",
            tools: ["Read", "Write"],
            infer: true
        },
        {
            name: "implementer",
            displayName: "Developer",
            description: "Implements solutions",
            prompt: "You are a senior developer. Write production-ready code.",
            tools: ["Read", "Write", "Bash"],
            infer: true
        }
    ]
});

// Workflow: requirements -> design -> implement
await session.sendAndWait({
    prompt: "@requirements-analyst Analyze the feature request in REQUIREMENTS.md"
});

await session.sendAndWait({
    prompt: "@architect Design a solution for the analyzed requirements"
});

await session.sendAndWait({
    prompt: "@implementer Implement the designed solution"
});
```

---

## Advanced Tool Patterns

### Stateful Tools

Maintain state across invocations:

```typescript
class SessionState {
    private cache = new Map();
    
    async getTool() {
        return defineTool("cache_operation", {
            description: "Cache get/set operations",
            parameters: z.object({
                operation: z.enum(["get", "set"]),
                key: z.string(),
                value: z.any().optional()
            }),
            handler: async ({ operation, key, value }) => {
                if (operation === "get") {
                    const cached = this.cache.get(key);
                    return {
                        textResultForLlm: cached ? `Found: ${cached}` : "Not cached",
                        resultType: "success"
                    };
                } else {
                    this.cache.set(key, value);
                    return {
                        textResultForLlm: `Cached ${key}`,
                        resultType: "success"
                    };
                }
            }
        });
    }
}

const stateManager = new SessionState();
const session = await client.createSession({
    tools: [await stateManager.getTool()]
});
```

### Async Resource Tools

Tools that manage external resources:

```typescript
const databaseTool = defineTool("db_query", {
    description: "Execute database query",
    parameters: z.object({
        query: z.string().describe("SQL query"),
        timeout: z.number().default(5000)
    }),
    handler: async ({ query, timeout }) => {
        const connection = await db.connect();
        try {
            const result = await connection.query(query, { timeout });
            return {
                textResultForLlm: `Query returned ${result.rows.length} rows`,
                resultType: "success",
                toolTelemetry: { rowCount: result.rows.length }
            };
        } catch (error) {
            return {
                textResultForLlm: `Query failed: ${error.message}`,
                resultType: "failure",
                error: error.message
            };
        } finally {
            await connection.close();
        }
    }
});
```

---

## Best Practices

### 1. Clear Descriptions
```typescript
// ✅ Good
description: "Create a new user account with email validation and role assignment"

// ❌ Poor
description: "Create user"
```

### 2. Defensive Input Validation
```typescript
// ✅ Good: Validate in Zod schema
parameters: z.object({
    email: z.string().email().describe("Valid email address"),
    age: z.number().min(18).max(120).describe("User age")
})

// ❌ Poor: No validation
parameters: z.object({
    email: z.string(),
    age: z.number()
})
```

### 3. Informative Results
```typescript
// ✅ Good: Includes context
return {
    textResultForLlm: "User john@example.com created with ID 12345",
    resultType: "success",
    toolTelemetry: { userId: 12345, email: "john@example.com" }
};

// ❌ Poor: Minimal info
return { textResultForLlm: "Done", resultType: "success" };
```

### 4. Error Handling
```typescript
// ✅ Good: Catch and return failure
try {
    await risky_operation();
} catch (error) {
    return {
        textResultForLlm: `Operation failed: ${error.message}`,
        resultType: "failure",
        error: error.code
    };
}

// ❌ Poor: Propagate exceptions
throw new Error("Operation failed");  // Breaks session
```

### 5. Tool Naming
```typescript
// ✅ Good: Clear, snake_case
"create_user", "send_email", "list_repositories"

// ❌ Poor: Ambiguous, mixed case
"makeUser", "email", "repos"
```
