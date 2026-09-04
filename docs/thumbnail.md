This DDL script defines a comprehensive database schema for managing information about community organisations. 
The schema, named "community_orgs," consists of 12 interconnected tables that capture various aspects of organisational data. 

Here's a description of the database structure:

## Core Table

The central table is "organisations," which stores basic information about each organisation, including:

- Legal name
- Trading name
- Date established
- Creation and modification timestamps
- User identifiers for insertion and last edit

## Related Tables

The remaining 11 tables are linked to the "organisations" table through foreign key relationships, each focusing on a specific aspect of organisational data:

1. **Accreditation**: Tracks certifications and accreditations.
2. **Contact Info**: Stores contact details, including physical and postal addresses, phone, email, website, and social media information.
3. **Financial Info**: Records funding sources, annual budget, financial year-end, and auditor details.
4. **Governance**: Contains information about board structure, constitution, and organisational chart.
5. **Historical Info**: Captures founding members, milestones, and structural changes over time.
6. **Legal Details**: Stores entity type, ABN, ACN, ACNC status, tax status, and insurance details.
7. **Operational Details**: Includes service area, target demographics, operating hours, staff counts, supported languages, and accessibility features.
8. **Performance Metrics**: Tracks various performance indicators and their values over time.
9. **Programs Services**: Details the programs and services offered, including descriptions and fee structures.
10. **Relationships**: Records partnerships and relationships with other organisations.
11. **Resources Assets**: Manages information about organisational assets and resources.

## Common Features

All tables share some common attributes:

- Auto-incrementing primary keys
- Timestamps for insertion and last edit
- User identifiers (UUID) for insertion and last edit

## Data Types and Structures

The schema utilizes a variety of data types to efficiently store information:

- Text and character varying for strings
- Integer and numeric for numerical data
- Date and timestamp for temporal data
- JSONB for flexible, structured data (e.g., social media profiles, board structures)
- Arrays for multiple values (e.g., funding sources, languages supported)

## Schema Design

The design defines a comprehensive schema for managing detailed information about community organisations.

The design follows a normalized approach, separating different aspects of organisational data into distinct tables. 
This structure allows for efficient data management and querying while maintaining data integrity through foreign key relationships.


