# C4 Model Architecture Template

This template provides a structured approach to documenting a system's architecture using the C4 model.

## 1. System Context (Level 1)

**Purpose:** Document the system in its environment, showing users and external dependencies.

```mermaid
C4Context
    title System Context for [System Name]

    Person(user, "User/Persona", "Brief description of the user and their goals.")
    System(system, "[System Name]", "The system being designed.")
    System_Ext(external, "External System", "External system that [System Name] depends on.")

    Rel(user, system, "Action / Use Case", "Protocol (e.g., HTTPS)")
    Rel(system, external, "Action / Integration", "Protocol (e.g., REST)")
```

## 2. Containers (Level 2)

**Purpose:** Show the high-level technical building blocks (apps, databases, services).

```mermaid
C4Container
    title Container diagram for [System Name]

    Person(user, "User", "Description")

    System_Boundary(boundary, "[System Name]") {
        Container(web_app, "Web Application", "Technology Stack", "Brief description")
        Container(api, "API Application", "Technology Stack", "Brief description")
        ContainerDb(db, "Database", "Database Technology", "Brief description")
    }

    Rel(user, web_app, "Action", "Protocol")
    Rel(web_app, api, "Uses", "Protocol")
    Rel(api, db, "Reads/Writes", "JDBC/etc")
```

## 3. Components (Level 3)

**Purpose:** Zoom into a specific container to show its internal structure.

```mermaid
C4Component
    title Component diagram for [Container Name]

    Container_Boundary(boundary, "[Container Name]") {
        Component(controller, "Controller/Handler", "Framework", "Input validation and routing")
        Component(service, "Business Service", "Language", "Core business logic")
        Component(repository, "Data Access", "Framework", "Database abstraction")
    }

    ContainerDb(db, "Database", "Technology")

    Rel(controller, service, "Calls")
    Rel(service, repository, "Uses")
    Rel(repository, db, "Queries")
```

## 4. Deployment (Optional)

**Purpose:** Map containers to infrastructure.

```mermaid
C4Deployment
    title Deployment Diagram for [System Name]

    Deployment_Node(cloud, "Cloud Provider", "Region/Zone") {
        Deployment_Node(node1, "Compute Instance", "Specs") {
            Container(app, "Application", "Tech Stack")
        }
        Deployment_Node(node2, "Database Instance", "Specs") {
            ContainerDb(db, "Database", "Tech Stack")
        }
    }

    Rel(app, db, "Connects to")
```

## 5. Summary Table

| Level         | Audience                          | Focus                                |
| ------------- | --------------------------------- | ------------------------------------ |
| 1. Context    | Stakeholders, Business, Technical | External dependencies and users      |
| 2. Container  | Architects, Technical Leads       | Services, apps, and data stores      |
| 3. Component  | Developers                        | Internal modules and interactions    |
| 4. Deployment | DevOps, SRE                       | Infrastructure and hosting resources |
