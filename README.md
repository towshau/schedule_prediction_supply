# Coach Schedule Supply System

## 📋 Overview

The **Coach Schedule Supply System** manages coach availability, scheduling preferences, and capacity allocation for Biomap's coaching operations. This system ensures optimal coach-to-member ratios while respecting individual coach preferences and constraints.

---

## 🎯 Purpose

This system:
- **Captures** coach scheduling preferences (HARD constraints, SOFT preferences, PREFERRED slots)
- **Tracks** coach availability across weekly time blocks
- **Manages** coach capacity (RM ceiling) and current load
- **Optimizes** schedule assignments based on preferences and business needs
- **Monitors** coach utilization and workload distribution

---

## 🏗️ System Architecture

```mermaid
graph TB
    subgraph "Coach Supply System"
        A[Coach Preferences] --> B[Schedule Validation]
        B --> C[Capacity Analysis]
        C --> D[Schedule Optimization]
        D --> E[Assignment Output]
        
        F[Staff Database] --> C
        G[Member Database] --> C
        
        E --> H[Coach Schedules]
        E --> I[Capacity Reports]
    end
    
    style A fill:#e1f5ff
    style E fill:#d4edda
    style D fill:#fff3cd
```

---

## 📊 Database Schema

### Core Tables

```mermaid
erDiagram
    STAFF_DATABASE ||--o{ SCHEDULE_PREFERENCES : submits
    SCHEDULE_PREFERENCES }o--|| SCHEDULE_PERIODS : "belongs to"
    STAFF_DATABASE ||--o{ MEMBER_MEMBERSHIPS : coaches
    
    STAFF_DATABASE {
        uuid id PK
        text coach_name
        text role
        enum staff_status
        int rm_ceiling
        text home_gym
        bool tod_coaching
        int style_relator
        int style_transformer
        int style_snc
        int style_specialist
        int style_wellness
    }
    
    SCHEDULE_PREFERENCES {
        uuid id PK
        uuid staff_id FK
        uuid period_id FK
        enum block
        enum preference_type
        int rank
        timestamp submitted_at
        text status
        enum valid
        text coach_name
    }
    
    SCHEDULE_PERIODS {
        uuid id PK
        date start_date
        date end_date
        text period_name
        enum status
    }
    
    MEMBER_MEMBERSHIPS {
        uuid id PK
        uuid coach_id FK
        uuid handoff_coach_id FK
        uuid member_id
        date start_date
        date end_date
        enum membership_stage
        enum status
        uuid primary_membership_id
    }
```

---

## 🗓️ Time Block Structure

### Weekly Schedule Grid

The system divides each weekday into **5 time blocks**, creating a **5×5 grid** (25 total blocks per week):

```mermaid
graph LR
    subgraph "Monday"
        M1[MON_EARLY]
        M2[MON_MID]
        M3[MON_LUNCH]
        M4[MON_ARVO]
        M5[MON_LATE]
    end
    
    subgraph "Tuesday"
        T1[TUE_EARLY]
        T2[TUE_MID]
        T3[TUE_LUNCH]
        T4[TUE_ARVO]
        T5[TUE_LATE]
    end
    
    subgraph "Wednesday"
        W1[WED_EARLY]
        W2[WED_MID]
        W3[WED_LUNCH]
        W4[WED_ARVO]
        W5[WED_LATE]
    end
    
    subgraph "Thursday"
        TH1[THU_EARLY]
        TH2[THU_MID]
        TH3[THU_LUNCH]
        TH4[THU_ARVO]
        TH5[THU_LATE]
    end
    
    subgraph "Friday"
        F1[FRI_EARLY]
        F2[FRI_MID]
        F3[FRI_LUNCH]
        F4[FRI_ARVO]
        F5[FRI_LATE]
    end
    
    style M1 fill:#e3f2fd
    style T1 fill:#e3f2fd
    style W1 fill:#e3f2fd
    style TH1 fill:#e3f2fd
    style F1 fill:#e3f2fd
```

**Time Block Definitions:**
- **EARLY**: Morning sessions (6:00 AM - 9:00 AM)
- **MID**: Mid-morning sessions (9:00 AM - 12:00 PM)
- **LUNCH**: Lunchtime sessions (12:00 PM - 2:00 PM)
- **ARVO**: Afternoon sessions (2:00 PM - 5:00 PM)
- **LATE**: Evening sessions (5:00 PM - 8:00 PM)

---

## 🎯 Preference Types

### Hierarchy of Constraints

```mermaid
graph TD
    A[Schedule Preferences] --> B[HARD Constraints]
    A --> C[SOFT Preferences]
    A --> D[PREFERRED Slots]
    
    B --> B1["❌ Must NOT be scheduled<br/>✅ Must HAVE this slot"]
    C --> C1["⚠️ Would prefer to avoid<br/>👍 Would like to have"]
    D --> D1["⭐ Ideal time slots<br/>🎯 Optimal for coach"]
    
    style B fill:#ffcdd2
    style C fill:#fff9c4
    style D fill:#c8e6c9
```

### Preference Type Definitions

1. **HARD** - Non-negotiable constraints
   - Absolute blockers (e.g., childcare, other commitments)
   - Must-have slots for business continuity
   - Overrides all other considerations

2. **SOFT** - Strong preferences
   - Coach work-life balance preferences
   - Preferred coaching times based on energy levels
   - Can be overridden for business needs

3. **PREFERRED** - Ideal scenarios
   - Optimal coaching slots
   - Best member availability alignment
   - Lowest priority in constraint solving

---

## 🔄 Preference Submission Flow

```mermaid
flowchart TD
    Start([Coach Opens Preference Form]) --> Input[Enter Time Block Preferences]
    Input --> Type{Select Preference Type}
    
    Type -->|HARD| Hard[Mark as HARD Constraint]
    Type -->|SOFT| Soft[Mark as SOFT Preference]
    Type -->|PREFERRED| Pref[Mark as PREFERRED Slot]
    
    Hard --> Validate[Validate Submission]
    Soft --> Validate
    Pref --> Validate
    
    Validate --> Check{Valid?}
    Check -->|No| Error[Show Validation Errors]
    Error --> Input
    
    Check -->|Yes| Submit[Submit to Database]
    Submit --> Period[Link to Schedule Period]
    Period --> Confirm[Confirmation + Timestamp]
    Confirm --> End([Preferences Saved])
    
    style Hard fill:#ffcdd2
    style Soft fill:#fff9c4
    style Pref fill:#c8e6c9
    style Confirm fill:#d4edda
```

---

## 📈 Coach Capacity Management

### RM (Relationship Management) Ceiling System

```mermaid
mindmap
    root((Coach Capacity))
        RM Ceiling
            Max client load
            Role-based limits
            Experience factor
        Current Load
            Primary Members
            Handoff Members
            Indefinite Holds
        Available Capacity
            RM Ceiling - Total Members
            New client allocation
            Handoff availability
        Utilization
            Percentage capacity
            Workload balance
            Distribution metrics
```

### Capacity Calculation

**Formula:**
```
Available Capacity = RM Ceiling - (Primary Members + Handoff Members)
```

**Member Count Rules:**
- Count **active members** with `end_date > CURRENT_DATE`
- Exclude `nosale` memberships
- Include **indefinite holds** within membership duration
- Exclude dependent/family memberships (`primary_membership_id IS NULL`)
- Count each member only **once** per coach

---

## 🔍 Supply-Side Metrics

### Key Performance Indicators

```mermaid
graph LR
    subgraph "Coach Supply Metrics"
        A[Total Coaches] --> B[Active Coaches]
        B --> C[Available Capacity]
        C --> D[Utilization Rate]
        
        E[Preference Coverage] --> F[Schedule Conflicts]
        F --> G[Optimization Score]
        
        H[Time Block Coverage] --> I[Peak vs. Off-Peak]
        I --> J[Coverage Gaps]
    end
    
    style C fill:#d4edda
    style F fill:#fff3cd
    style J fill:#ffcdd2
```

**Metrics Tracked:**
1. **Coach Availability**: Percentage of time blocks with available coaches
2. **Preference Satisfaction**: % of preferences honored in final schedule
3. **Capacity Utilization**: Average % of RM ceiling utilized
4. **Coverage Gaps**: Time blocks with insufficient coach coverage
5. **Constraint Violations**: Number of HARD constraints broken (should be 0)

---

## 🛠️ Setup & Configuration

### Prerequisites

- PostgreSQL 12+ (via Supabase)
- Access to `staff_database`, `schedule_preferences`, `member_memberships`
- Retool account for dashboard/UI

### Database Setup

```sql
-- Verify schedule_preferences table exists
SELECT * FROM information_schema.tables 
WHERE table_name = 'schedule_preferences';

-- Check for existing preferences
SELECT 
    COUNT(*) as total_preferences,
    COUNT(DISTINCT staff_id) as unique_coaches,
    COUNT(DISTINCT period_id) as unique_periods
FROM schedule_preferences;
```

---

## 📊 Usage Examples

### Query Coach Preferences for a Period

```sql
SELECT 
    sp.coach_name,
    sp.block,
    sp.preference_type,
    sp.submitted_at,
    sp.valid
FROM schedule_preferences sp
WHERE sp.period_id = 'YOUR_PERIOD_ID'
    AND sp.valid = 'yes'
ORDER BY sp.coach_name, sp.block;
```

### Find Schedule Conflicts

```sql
WITH hard_blocks AS (
    SELECT 
        staff_id,
        coach_name,
        block,
        COUNT(*) as duplicate_count
    FROM schedule_preferences
    WHERE preference_type = 'HARD'
        AND period_id = 'YOUR_PERIOD_ID'
    GROUP BY staff_id, coach_name, block
    HAVING COUNT(*) > 1
)
SELECT * FROM hard_blocks;
```

### Calculate Coverage by Time Block

```sql
SELECT 
    sp.block,
    COUNT(DISTINCT sp.staff_id) as available_coaches,
    STRING_AGG(sp.coach_name, ', ' ORDER BY sp.coach_name) as coach_list
FROM schedule_preferences sp
JOIN staff_database sd ON sp.staff_id = sd.id
WHERE sp.preference_type IN ('PREFERRED', 'SOFT')
    AND sd.staff_status = 'active'
    AND sp.period_id = 'YOUR_PERIOD_ID'
GROUP BY sp.block
ORDER BY sp.block;
```

### Coach Capacity Overview

```sql
SELECT 
    s.coach_name,
    s.rm_ceiling,
    COUNT(DISTINCT CASE 
        WHEN m.end_date > CURRENT_DATE 
        AND m.membership_stage <> 'nosale'
        AND m.primary_membership_id IS NULL 
        THEN m.member_id 
    END) AS current_members,
    s.rm_ceiling - COUNT(DISTINCT CASE 
        WHEN m.end_date > CURRENT_DATE 
        AND m.membership_stage <> 'nosale'
        AND m.primary_membership_id IS NULL 
        THEN m.member_id 
    END) AS available_capacity,
    ROUND(
        COUNT(DISTINCT CASE 
            WHEN m.end_date > CURRENT_DATE 
            AND m.membership_stage <> 'nosale'
            AND m.primary_membership_id IS NULL 
            THEN m.member_id 
        END)::numeric / NULLIF(s.rm_ceiling, 0) * 100, 
        2
    ) AS utilization_pct
FROM staff_database s
LEFT JOIN member_memberships m ON s.id = m.coach_id
WHERE s.staff_status = 'active'
    AND s.role IN ('Coach', 'Senior Coach', 'Advanced Coach', 'Head Coach', 'Gym Manager')
GROUP BY s.id, s.coach_name, s.rm_ceiling
ORDER BY utilization_pct DESC NULLS LAST;
```

---

## 🎨 Retool Dashboard Components

### 1. Coach Preference Calendar

**Component Type:** Calendar or Grid View

**Data Source Query:**
```sql
SELECT 
    sp.id,
    sp.coach_name,
    sp.block,
    sp.preference_type,
    sp.submitted_at,
    CASE 
        WHEN sp.preference_type = 'HARD' THEN '#ff5252'
        WHEN sp.preference_type = 'SOFT' THEN '#ffd54f'
        WHEN sp.preference_type = 'PREFERRED' THEN '#81c784'
    END as color
FROM schedule_preferences sp
WHERE sp.period_id = {{ periodSelector.value }}
    AND sp.staff_id = {{ coachSelector.selectedRow.id }}
ORDER BY sp.block;
```

**Display:**
- Grid layout: Days (columns) × Time Blocks (rows)
- Color-coded by preference type
- Click to view/edit preference details

### 2. Capacity Dashboard

**Component Type:** Table with Summary Row

**Data Source:** Use the "Coach Capacity Overview" query above

**Columns:**
- Coach Name
- RM Ceiling
- Current Members
- Available Capacity
- Utilization %

**Summary Row:**
- Total RM Ceiling: `SUM`
- Average Utilization: `AVG`
- Total Available Capacity: `SUM`

### 3. Coverage Heatmap

**Component Type:** Plotly Chart (Heatmap)

**Data Transformation:**
```javascript
// Transform data for heatmap
const days = ['MON', 'TUE', 'WED', 'THU', 'FRI'];
const times = ['EARLY', 'MID', 'LUNCH', 'ARVO', 'LATE'];

const coverageData = coverageQuery.data.reduce((acc, row) => {
    const [day, time] = row.block.split('_');
    if (!acc[time]) acc[time] = {};
    acc[time][day] = row.available_coaches;
    return acc;
}, {});

const z = times.map(time => 
    days.map(day => coverageData[time]?.[day] || 0)
);

return [{
    type: 'heatmap',
    x: days,
    y: times,
    z: z,
    colorscale: 'RdYlGn',
    hoverongaps: false
}];
```

---

## 🔧 Optimization Algorithm

### Constraint Satisfaction Approach

```mermaid
flowchart TD
    Start([Begin Schedule Optimization]) --> Load[Load All Preferences]
    Load --> Sort[Sort by Priority:<br/>HARD > SOFT > PREFERRED]
    
    Sort --> Process{Process Each Block}
    
    Process --> Check[Check Constraints]
    Check --> Hard{HARD<br/>Violations?}
    
    Hard -->|Yes| Reject[Reject Assignment]
    Hard -->|No| Soft{Optimize SOFT<br/>Preferences?}
    
    Soft -->|Yes| Score1[+2 Score]
    Soft -->|No| Score2[+0 Score]
    
    Score1 --> Pref{PREFERRED<br/>Match?}
    Score2 --> Pref
    
    Pref -->|Yes| Score3[+1 Score]
    Pref -->|No| Score4[+0 Score]
    
    Score3 --> Capacity{Check<br/>Capacity}
    Score4 --> Capacity
    
    Capacity -->|Available| Assign[Assign to Block]
    Capacity -->|Full| Skip[Skip to Next]
    
    Assign --> More{More<br/>Blocks?}
    Skip --> More
    Reject --> More
    
    More -->|Yes| Process
    More -->|No| Output[Generate Schedule]
    
    Output --> Validate[Validate Coverage]
    Validate --> Report[Generate Report]
    Report --> End([Schedule Complete])
    
    style Hard fill:#ffcdd2
    style Assign fill:#c8e6c9
    style Report fill:#e1f5ff
```

**Scoring System:**
- **HARD satisfied**: Required (or reject)
- **SOFT satisfied**: +2 points
- **PREFERRED satisfied**: +1 point
- **Capacity within limits**: Required
- **Coverage gaps**: -5 points per gap

**Optimization Goal:** Maximize total score while maintaining 100% HARD constraint satisfaction and minimum coverage requirements.

---

## 📚 Data Dictionary

### `schedule_preferences` Table

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `id` | UUID | Unique preference identifier | `c161e14a-0d07-4ce6-9a83-cc3bfc5c267a` |
| `staff_id` | UUID | Foreign key to `staff_database.id` | `1d357192-48b5-4390-a80e-88d68aedf24d` |
| `period_id` | UUID | Foreign key to schedule period | `bceb1735-9c09-440f-9277-b9bce2849839` |
| `block` | ENUM | Time block identifier | `MON_LATE`, `WED_EARLY` |
| `preference_type` | ENUM | Constraint severity | `HARD`, `SOFT`, `PREFERRED` |
| `rank` | INTEGER | Priority ranking (optional) | `1`, `2`, `3` |
| `submitted_at` | TIMESTAMP | Submission datetime | `2026-01-12 00:00:00+00` |
| `status` | TEXT | Processing status | `pending`, `approved`, `rejected` |
| `valid` | ENUM | Validation flag | `yes`, `no` |
| `coach_name` | TEXT | Coach name (denormalized) | `Aaron Kidd` |

### Time Blocks (25 total)

| Pattern | Examples |
|---------|----------|
| `{DAY}_EARLY` | `MON_EARLY`, `TUE_EARLY`, `WED_EARLY`, `THU_EARLY`, `FRI_EARLY` |
| `{DAY}_MID` | `MON_MID`, `TUE_MID`, `WED_MID`, `THU_MID`, `FRI_MID` |
| `{DAY}_LUNCH` | `MON_LUNCH`, `TUE_LUNCH`, `WED_LUNCH`, `THU_LUNCH`, `FRI_LUNCH` |
| `{DAY}_ARVO` | `MON_ARVO`, `TUE_ARVO`, `WED_ARVO`, `THU_ARVO`, `FRI_ARVO` |
| `{DAY}_LATE` | `MON_LATE`, `TUE_LATE`, `WED_LATE`, `THU_LATE`, `FRI_LATE` |

---

## 🚀 Features

- ✅ **Multi-period scheduling** - Support for multiple scheduling periods
- ✅ **Hierarchical preferences** - HARD, SOFT, PREFERRED constraint types
- ✅ **Capacity tracking** - Real-time RM ceiling and utilization monitoring
- ✅ **Conflict detection** - Automatic identification of scheduling conflicts
- ✅ **Coverage analysis** - Identify gaps in time block coverage
- ✅ **Audit trail** - Track preference submissions and changes
- ✅ **Coach analytics** - Detailed utilization and workload metrics

---

## 🔮 Future Enhancements

1. **Automated Scheduling Engine**
   - Constraint satisfaction solver
   - Genetic algorithm for optimization
   - Machine learning for preference prediction

2. **Mobile Preference Submission**
   - iOS/Android app integration
   - Push notifications for schedule changes
   - Real-time availability updates

3. **Advanced Analytics**
   - Predictive capacity modeling
   - Member-coach matching optimization
   - Burnout risk detection

4. **Integration Modules**
   - Calendar sync (Google, Outlook)
   - Member booking system integration
   - Automated shift swap marketplace

---

## 🤝 Contributing

This is an internal Biomap system. For questions or suggestions:

1. Submit issues via the GitHub issue tracker
2. Contact the operations team for access requests
3. Follow internal code review processes for changes

---

## 📞 Support

**System Maintainer:** Biomap Operations Team  
**Database:** Supabase (PostgreSQL)  
**Dashboard:** Retool  
**Repository:** [schedule_prediction_supply](https://github.com/towshau/schedule_prediction_supply)

---

## 📄 License

Internal use only - Biomap proprietary system

---

**Last Updated:** January 2026  
**Version:** 1.0.0
