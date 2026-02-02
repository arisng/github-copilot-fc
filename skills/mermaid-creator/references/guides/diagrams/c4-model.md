# C4 Model Diagrams Guide

The **C4 model** (Context, Container, Component, and Code) is an "abstractions-first" approach to software architecture. Mermaid provides specialized syntax for C4 diagrams that follow the official C4 model styling.

---

## 1. C4 Context Diagram (L1)

**Purpose:** Show the system boundary and how it fits in its environment.

```mermaid
C4Context
    title System Context diagram for Internet Banking System

    Person(customer, "Banking Customer", "A customer of the bank, with personal bank accounts.")
    System(banking_system, "Internet Banking System", "Allows customers to view information about their bank accounts, and make payments.")

    System_Ext(mail_system, "E-mail System", "The internal Microsoft Exchange e-mail system.")
    System_Ext(mainframe, "Mainframe Banking System", "Stores all of the core banking information about customers, accounts, transactions, etc.")

    Rel(customer, banking_system, "Uses")
    Rel(banking_system, mail_system, "Sends e-mail using")
    Rel(mail_system, customer, "Sends e-mails to")
    Rel(banking_system, mainframe, "Uses")
```

---

## 2. C4 Container Diagram (L2)

**Purpose:** Show the major runtime containers (applications, databases, services) that make up the system.

```mermaid
C4Container
    title Container diagram for Internet Banking System

    Person(customer, "Customer", "A customer of the bank, with personal bank accounts.")

    System_Boundary(c1, "Internet Banking") {
        Container(web_app, "Web Application", "Java, Spring MVC", "Delivers the static content and the internet banking SPA")
        Container(spa, "Single-Page App", "JavaScript, Angular", "Provides all the internet banking functionality to customers via their web browser")
        Container(mobile_app, "Mobile App", "C#, Xamarin", "Provides a limited subset of the internet banking functionality to customers via their mobile device")
        ContainerDb(database, "Database", "SQL Database", "Stores user registration information, hashed auth credentials, access logs, etc.")
        Container(api, "API Application", "Java, Spring Boot", "Provides internet banking functionality via a JSON/HTTPS API")
    }

    System_Ext(mail_system, "E-mail System", "The internal Microsoft Exchange e-mail system.")
    System_Ext(mainframe, "Mainframe Banking System", "Stores all of the core banking information about customers, accounts, transactions, etc.")

    Rel(customer, web_app, "Uses", "HTTPS")
    Rel(customer, spa, "Uses", "HTTPS")
    Rel(customer, mobile_app, "Uses")

    Rel(web_app, spa, "Delivers")
    Rel(spa, api, "Uses", "async, JSON/HTTPS")
    Rel(mobile_app, api, "Uses", "async, JSON/HTTPS")
    Rel_L(api, database, "Reads from and writes to", "JDBC")

    Rel(api, mail_system, "Sends e-mails using", "SMTP")
    Rel(api, mainframe, "Uses", "XML/HTTPS")
```

---

## 3. C4 Component Diagram (L3)

**Purpose:** Zoom into a single container to show its internal components.

```mermaid
C4Component
    title Component diagram for API Application

    Container_Boundary(b1, "API Application") {
        Component(sign_in_controller, "Sign In Controller", "Spring MVC RestController", "Allows users to sign in to the banking system")
        Component(security_component, "Security Component", "Spring Bean", "Provides functionality related to signing in, changing passwords, etc.")
        Component(reset_password_controller, "Reset Password Controller", "Spring MVC RestController", "Allows users to reset their passwords")
        Component(email_component, "E-mail Component", "Spring Bean", "Sends e-mails to users")
    }

    ContainerDb(database, "Database", "SQL Database", "Stores user registration information, hashed auth credentials, access logs, etc.")
    System_Ext(mail_system, "E-mail System", "The internal Microsoft Exchange e-mail system.")

    Rel(sign_in_controller, security_component, "Uses")
    Rel(security_component, database, "Reads from and writes to", "JDBC")
    Rel(reset_password_controller, security_component, "Uses")
    Rel(reset_password_controller, email_component, "Uses")
    Rel(email_component, mail_system, "Sends e-mail using", "SMTP")
```

---

## 4. C4 Dynamic Diagram (Behavioral)

**Purpose:** Show how components in a C4 model interact at runtime (similar to sequence diagram but using C4 elements).

```mermaid
C4Dynamic
    title Dynamic diagram for API Application

    Person(customer, "Customer", "A customer of the bank")
    Container(spa, "Single-Page App", "JavaScript, Angular", "Provides banking functionality")
    Component(sign_in_controller, "Sign In Controller", "Spring MVC RestController", "Allows users to sign in")
    Component(security_component, "Security Component", "Spring Bean", "Validates credentials")
    ContainerDb(database, "Database", "SQL Database", "Stores credentials")

    Rel(customer, spa, "Submits credentials to")
    Rel(spa, sign_in_controller, "Calls sign-in endpoint", "JSON/HTTPS")
    Rel(sign_in_controller, security_component, "Calls authenticate()")
    Rel(security_component, database, "Queries user credentials", "JDBC")
```

---

## 5. C4 Deployment Diagram (L4V)

**Purpose:** Show how containers are mapped to infrastructure.

```mermaid
C4Deployment
    title Deployment Diagram - Internet Banking System

    Deployment_Node(mob, "Customer's mobile device", "Apple iOS or Android") {
        Container(mobile, "Mobile App", "Xamarin", "Provides a limited subset of functionality")
    }

    Deployment_Node(comp, "Customer's computer", "Microsoft Windows or Apple macOS") {
        Deployment_Node(browser, "Web Browser", "Google Chrome, Mozilla Firefox, Apple Safari or Microsoft Edge") {
            Container(spa, "Single-Page App", "Angular", "Provides all functionality via browser")
        }
    }

    Deployment_Node(plc, "Big Bank plc", "Big Bank plc data center") {
        Deployment_Node(dn, "bigbank-web***", "Ubuntu 22.04 LTS", "Web Server Node") {
            Deployment_Node(apache, "Apache Tomcat", "Apache Tomcat 10.x", "Servlet Container") {
                Container(web, "Web Application", "Java, Spring MVC", "Delivers static content and SPA")
            }
        }
        Deployment_Node(db, "bigbank-db01", "Ubuntu 22.04 LTS", "Database Server Node") {
            Deployment_Node(mysql, "MySQL", "MySQL 8.x", "Relational Database Management System") {
                ContainerDb(db_inst, "Database", "SQL Database", "Stores user info, etc.")
            }
        }
    }

    Rel(mobile, spa, "Makes API calls to", "json/https")
    Rel(spa, web, "Makes API calls to", "json/https")
    Rel(web, db_inst, "Reads from and writes to", "jdbc")
```

---

## Layout Optimization & Best Practices

To ensure C4 diagrams are readable and well-organized, follow these layout optimization strategies:

### 1. Avoid Deep Boundary Nesting
Deeply nesting `System_Boundary` or `Container_Boundary` inside another `Container_Boundary` often breaks the Mermaid layout engine. This can cause the engine to ignore directional hints and clump components in unpredictable ways.
**Strategy:** Flatten boundaries where possible to improve readability.

### 2. Definition Order and Ranking
The Sugiyama layout algorithm (used by Mermaid) treats nodes defined at the top of the `.mmd` file as "Upper Rank".
**Strategy:** To prevent downstream systems (Databases, External APIs) from floating to the top, define your internal components first and external/downstream systems later in the file.

### 3. Directional Hints vs. Ranking Logic
Directional hints like `Rel_D`, `Rel_L`, `Rel_R`, and `Rel_U` are suggestions, not strict commands. If internal ranking logic or boundary constraints contradict them, the hints may be ignored.
**Strategy:** Use `Rel_D` sparingly, primarily for terminal "Sink" nodes like databases or logging services. Rely on definition order for general flow.

### 4. Semantic Clustering
Don't try to model exact spatial geometry. Instead, group components by their functional role.
**Strategy:** Place related middleware or services in a logical sequence to create a clear "functional heatmap" of the system.

### 5. Visual Focus with Styles
Standard blue boxes can lead to "wall of blue" fatigue in complex diagrams. 
**Strategy:** Use `UpdateElementStyle` to apply distinct colors (e.g., Light Green for new features) to guide the reader's eye to high-priority areas.

### 6. "T-Shape" Flow vs. "Star" Flow
Avoid "Star" patterns where a central component has 5+ outgoing arrows, which leads to excessive line crossing.
**Strategy:** Prefer a vertical "Pipeline" for main processing flows and horizontal "Branches" for external integrations.

### 7. Text Conciseness
Overloading technical descriptions inside component boxes forces the layout engine to widen the boxes, stretching the entire diagram.
**Strategy:** Keep "Technology" and "Description" fields concise. Move deep technical details to the surrounding Markdown text rather than the diagram itself.

---

## General Tips

1. **Use Specialized Macros:** Use `Person()`, `System()`, `Container()`, `Component()` instead of generic nodes.
2. **Include Technology Stack:** Always specify technology in the third parameter (e.g., `"Java, Spring Boot"`).
3. **Boundary Clarity:** Use `System_Boundary()` and `Container_Boundary()` to group related items.
4. **Relationship Details:** Use the third and fourth parameters of `Rel()` to specify the action and protocol.

---

**Related Guides:**
- [Architecture Diagrams](./architecture-diagrams.md) - High-level conceptual views
- [Deployment Diagrams](./deployment-diagrams.md) - Infrastructure mapping
- [Unicode Symbols](../unicode-symbols/guide.md) - Complete symbol reference
