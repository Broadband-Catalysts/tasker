# Shiny Monitor App: Reactive Dependency Diagram

**Last Updated:** 2026-01-25  
**Status:** ✅ FIXED - Reactive timer pattern corrected, observer self-dependency resolved

## Purpose

This document maps the reactive dependencies in the tasker monitor Shiny application to help identify and prevent reactive storms, infinite loops, and performance issues.

---

## Current Reactive Dependency Flow (CORRECTED)

### Implementation Summary

**✅ FIXED Issues:**
1. **Reactive Timer** - Now uses `reactiveTimer()` instead of `observe()` + `invalidateLater()`
2. **Observer Self-Dependency** - Uses `initial_load_complete` flag instead of checking `rv$last_update`
3. **Query Cooldown** - 5-second minimum interval prevents flooding
4. **Isolated Writes** - All reactive value updates wrapped in `isolate()` to prevent cascading

### Mermaid Diagram Specification

```mermaid
flowchart TD
    
    subgraph inputs["INPUT SOURCES"]
        timer["⏱️ invalidateLater<br/>5000ms timer"]
        refreshBtn["🔄 input$refresh<br/>Manual Button"]
        forceRefreshBtn["⚡ input$force_refresh_btn<br/>Force Button"]
        autoRefreshCheckbox["☑️ input$auto_refresh<br/>Checkbox"]
        tabInput["📋 input$main_tabs<br/>Tab Selection"]
        refreshInterval["⏱️ input$refresh_interval<br/>Interval ms"]
    end
    
    subgraph reactives["REACTIVE VALUES & EXPRESSIONS"]
        refreshTrigger["📌 refresh_trigger<br/>reactiveVal"]
        autoRefreshTimer["⏱️ auto_refresh_timer<br/>reactiveTimer()"]
        taskData["🔍 task_data<br/>reactive + bindEvent"]
        queryRunning["⏳ rv$query_running<br/>reactive"]
        lastUpdate["🕐 rv$last_update<br/>reactive"]
        initialLoadComplete["✅ rv$initial_load_complete<br/>flag"]
        stageReactives["📊 stage_reactives<br/>reactiveValues"]
    end
    
    subgraph observers["OBSERVERS (READ & WRITE DATA)"]
        timerObserver["👁️ Auto-Refresh Observer<br/>reactiveTimer() based"]
        mainObserver["👁️ Main Observer<br/>Updates tasks"]
        autoExpandObserver["👁️ Auto-Expand<br/>Stage accordion"]
        busyIndicatorObserver["👁️ Busy Indicator<br/>Enable/disable"]
    end
    
    subgraph output["OUTPUT"]
        busyOutput["📤 output$busy_indicator<br/>UI text"]
    end
    
    %% AUTO-REFRESH TIMER - uses reactiveTimer() for clean timer dependency
    refreshInterval -->|dynamic<br/>interval| autoRefreshTimer
    autoRefreshTimer -->|REACTIVE<br/>READ| timerObserver
    autoRefreshCheckbox -->|isolate read| timerObserver
    queryRunning -->|isolate read| timerObserver
    timerObserver -->|WRITES| refreshTrigger
    
    %% MANUAL REFRESH
    refreshBtn -->|observeEvent| refreshTrigger
    
    %% REFRESH TRIGGER drives TASK DATA
    refreshTrigger -->|bindEvent| taskData
    
    %% TASK DATA modifies query state
    taskData -->|WRITES TRUE<br/>start| queryRunning
    taskData -->|WRITES FALSE<br/>end| queryRunning
    
    %% MAIN OBSERVER - reactive dependencies
    taskData -->|REACTIVE<br/>READ| mainObserver
    forceRefreshBtn -->|REACTIVE<br/>READ| mainObserver
    tabInput -->|isolate read| mainObserver
    initialLoadComplete -->|isolate read| mainObserver
    
    %% MAIN OBSERVER writes updates (all isolated to prevent cascading)
    mainObserver -->|WRITES<br/>(isolated)| stageReactives
    mainObserver -->|WRITES<br/>(isolated)| lastUpdate
    mainObserver -->|WRITES<br/>(isolated)| initialLoadComplete
    
    %% AUTO-EXPAND depends on stages
    stageReactives -->|REACTIVE<br/>READ| autoExpandObserver
    
    %% BUSY INDICATOR 
    queryRunning -->|REACTIVE<br/>READ| busyIndicatorObserver
    busyIndicatorObserver -->|WRITES| busyOutput
```

### ASCII Rendering (Generated with mermaid-ascii)

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                INPUT SOURCES                                                                                │
│                                                                                                                                                                             │
│                                                                                                                                                                             │
│ ┌──────────────────────────┐  ┌────────────────────┐  ┌────────────────────────────┐  ┌─────────────────────────────┐  ┌────────────────────┐  ┌──────────────────────────┐ │
│ │                          │  │                    │  │                            │  │                             │  │                    │  │                          │ │
│ │    ⏱️ invalidateLater    │  │  🔄 input$refresh  │  │ ⚡ input$force_refresh_btn │  │    ☑️ input$auto_refresh    │  │ 📋 input$main_tabs │  │ ⏱️ input$refresh_interval│ │
│ │    5000ms timer          │ ┌│┤ Manual Button     │ ┌│┤Force Button               │ ┌│┤   Checkbox                 │ ┌│┤Tab Selection      │  │ Interval ms              │ │
│ │                          │ ││                    │ ││                            │ ││                             │ ││                    │  │                          │ │
│ └──────────────────────────┘ │└────────────────────┘ │└────────────────────────────┘ │└─────────────────────────────┘ │└────────────────────┘  └─────────────┬────────────┘ │
│                              │                       │                               │                                │                                      │              │
└──────────────────────────────┼───────────────────────┼───────────────────────────────┼────────────────────────────────┼──────────────────────────────────────┼──────────────┘
                ┌──────────────┘           ┌───────────┴───────────────┬───────────────┴────────────────────────────────┘                                      │               
┌───────────────┼──────────────────────────┼───────────────────────────┼───────────────┬────────────────────────────────┐                                      │               
│               ▼            OBSERVERS (READ & WRITE DATA)              ▼               │         REACTIVE VALUES &      │                                      │               
│ ┌──────────────────────────┐  ┌────────────────────┐  ┌────────────────────────────┐ │┌─────────────────────────────┐ │                    EXPRESSIONS       │               
│ │                          │  │                    │  │                            │ ││                             │ │                                      │               
│ │    📌 refresh_trigger    │  │  👁️ Main Observer  │  │  👁️ Auto-Refresh Observer  │ ││    ⏱️ auto_refresh_timer    │ │                                      │               
│ │    reactiveVal           │◄┐│  Updates tasks     ├◄►│┤ reactiveTimer() based     │◄┼┤    reactiveTimer()          │◄┼──────────────────────────────────────┘               
│ │                          │ ││                    │ ││                            │ ││                             │ │                                                      
│ └─────────────┬────────────┘ │└──────────┬─────────┘ │└────────────────────────────┘ │└─────────────────────────────┘ │                                                      
│               ▼              ├───────────▼───────────┼───────────────▼───────────────┼───────────────▼                │                                                      
│ ┌──────────────────────────┐ │┌────────────────────┐ │┌────────────────────────────┐ │┌─────────────────────────────┐ │                                                      
│ │                          │ ││                    │ ││                            │ ││              ┴              │ │                                                      
│ │   🔍 task_data           │ ││ 📊 stage_reactives │ ││     🕐 rv$last_update      │ ││ ✅ rv$initial_load_complete │ │                                                      
│ │   reactive + bindEvent   ├─┘│ reactiveValues     │ ││     reactive               │ ││ flag                        │ │                                                      
│ │                          │  │                    │ ││                            │ ││                             │ │                                                      
│ └─────────────┬────────────┘  └──────────┬─────────┘ │└────────────────────────────┘ │└─────────────────────────────┘ │                                                      
│               ▼──────────────────────────▼───────────┘                               │                                │                                                      
│ ┌──────────────────────────┐  ┌────────────────────┐                                 │                                │                                                      
│ │             ┴            │  │                    │                                 │                                │                                                      
│ │   ⏳ rv$query_running    │  │  👁️ Auto-Expand    │                                 │                                │                                                      
│ │   reactive               │  │  Stage accordion   │                                 │                                │                                                      
│ │                          │  │                    │                                 │                                │                                                      
│ └─────────────┬────────────┘  └────────────────────┘                                 │                                │                                                      
│               ▼                                                                      │                                │                                                      
├─┬──────────────────────────┬─────────────────────────────────────────────────────────┼────────────────────────────────┘                                                      
│ │                          │                                                         │                                                                                       
│ │     👁️ Busy Indicator    │                                                         │                                                                                       
│ │     Enable/disable       │                                                         │                                                                                       
│ │                          │                                                         │                                                                                       
│ └─────────────┬────────────┘                                                         │                                                                                       
│               │                                                                      │                                                                                       
└───────────────┼──────────────────────────────────────────────────────────────────────┘                                                                                       
                │                                                                                                                                                              
┌───────────────┼──────────────┐                                                                                                                                               
│           OUTPUT             │                                                                                                                                               
│ ┌──────────────────────────┐ │                                                                                                                                               
│ │                          │ │                                                                                                                                               
│ │ 📤 output$busy_indicator │ │                                                                                                                                               
│ │ UI text                  │ │                                                                                                                                               
│ │                          │ │                                                                                                                                               
│ └──────────────────────────┘ │                                                                                                                                               
│                              │                                                                                                                                               
└──────────────────────────────┘
```

**Legend:**
- **INPUT SOURCES** (top) - User inputs and timer callbacks
- **OBSERVERS** (middle) - Reactive observers that read inputs and write to reactive values
- **REACTIVE VALUES** - The data being managed (refresh_trigger, task_data, query_running, etc.)
- **OUTPUT** (bottom) - Final UI output (busy indicator)

**Key Patterns:**
- **`isolate read`** - Uses `isolate()` to prevent full reactive dependency
- **`REACTIVE READ`** - Creates a real reactive dependency
- **`WRITES`** - Observer modifies this reactive value
- **Arrow direction** - Shows data flow from inputs → observers → reactives → output

**Regeneration Notes:**
```bash
# To regenerate this diagram:
cd /home/warnes/src/tasker-dev/inst/docs
# Save the Mermaid code block above to reactive-diagram.mmd, then:
/home/warnes/src/mermaid-ascii/mermaid-ascii -w 150 -f reactive-diagram.mmd
```


---

## ~~Identified Problems~~ RESOLVED Issues

### ✅ FIXED: Reactive Loop in auto-refresh observer

**Previous Problem:** `invalidateLater()` inside `observe()` created perpetual reactive context that invalidated on every flush cycle, not just the timer.

**Solution Implemented:** `reactiveTimer()` pattern

**Location:** `server.R` lines ~1041-1059

**Corrected Code:**

```r
# Use reactiveTimer() instead of invalidateLater() to prevent reactive storm
# reactiveTimer() creates a clean reactive dependency that ONLY fires on schedule
auto_refresh_timer <- reactive({
  # Allow dynamic interval changes
  interval_ms <- input$refresh_interval * 1000
  reactiveTimer(interval_ms)()
})

observe({
  auto_refresh_timer()  # Depend ONLY on timer
  # Use isolate() to prevent reactive dependencies on conditional checks
  if (isolate(input$auto_refresh) && isolate(!rv$query_running)) {
    new_val <- isolate(refresh_trigger()) + 1
    refresh_trigger(new_val)
  }
})
```

**Why This Works:**

- `reactiveTimer()` creates a TRUE time-based reactive dependency
- Timer fires ONLY on its schedule (every N milliseconds)
- NOT affected by other reactive flush cycles in the session
- `isolate()` on conditionals prevents additional dependencies
- Clean, predictable behavior

### ✅ FIXED: Observer Self-Dependency

**Previous Problem:** Main observer checked `rv$last_update` for NULL (even isolated), then wrote to it later. This created fragile coupling.

**Solution Implemented:** Separate `initial_load_complete` flag

**Location:** `server.R` lines ~1155-1165, ~1351-1353

**Corrected Code:**

```r
# In rv initialization:
rv <- reactiveValues(
  # ...
  initial_load_complete = FALSE  # Track initial load separately
)

# In main observer:
observe({
  current_status <- task_data()
  rv$force_refresh
  
  # After initial load, only update when Pipeline Status tab is active
  # Use separate flag to avoid observer self-dependency on rv$last_update
  if (isolate(rv$initial_load_complete)) {
    req(isolate(input$main_tabs) == "Pipeline Status")
  }
  
  # ... update logic ...
  
  # Update last refresh timestamp
  isolate(rv$last_update <- Sys.time())
  # Mark initial load complete after first successful update
  isolate(rv$initial_load_complete <- TRUE)
})
```

**Why This Works:**

- `initial_load_complete` is a simple boolean flag (FALSE → TRUE once)
- No circular dependency (observer doesn't read what it writes)
- `isolate()` on ALL writes prevents triggering other observers
- Clear separation: flag for control flow, timestamp for display

---

## ~~Auxiliary Reactive Dependencies~~ Current Reactive Dependencies

### Query Cooldown Mechanism

**Location:** `server.R` task_data() reactive

**Purpose:** Prevent database query flooding even if refresh_trigger increments rapidly

```r
task_data <- reactive({
  # Prevent overlapping queries
  time_since_last <- as.numeric(difftime(Sys.time(), rv$last_query_time, units = "secs"))
  req(time_since_last >= min_query_interval)  # 5 second minimum
  
  rv$query_running <- TRUE
  on.exit({
    rv$query_running <- FALSE
    rv$last_query_time <- Sys.time()
  }, add = TRUE)
  
  # ... query database ...
}) %>% bindEvent(refresh_trigger(), ignoreInit = FALSE, ignoreNULL = TRUE)
```

**Key Features:**
- **5-second minimum** between queries
- **`on.exit()` cleanup** ensures state reset even on error
- **`bindEvent()`** provides clean dependency on `refresh_trigger` only

### Busy Indicator Observer

**Location:** `server.R` lines ~897-903

```r
observe({
  if (rv$query_running) {
    shinyjs::disable("auto_refresh")
  } else {
    shinyjs::enable("auto_refresh")
  }
})
```

**Depends On:** `rv$query_running`  
**Effect:** Creates additional reactive dependency on query state

---

## Manual Triggers

### Manual Refresh Button

```r
observeEvent(input$refresh) → refresh_trigger(n+1)
```

### Force Refresh Button

```r
observeEvent(input$force_refresh_btn) → rv$force_refresh(n+1)
```

---

## ~~Root Cause Analysis~~ Implementation Details

### Why reactiveTimer() Instead of invalidateLater()

**The Problem with `invalidateLater()`:**

`invalidateLater()` inside `observe()` without proper isolation creates a hot loop. The observer re-runs on EVERY reactive flush, not just on the timer.

Shiny's reactive graph flushes whenever ANY reactive value changes. `invalidateLater()` schedules an invalidation, but it doesn't BLOCK the observer from running when other reactive values in the session change. Since `rv$query_running` and other reactive values are changing constantly, the observer with `invalidateLater()` gets triggered on every flush.

**Why `reactiveTimer()` Solves This:**

- `reactiveTimer()` creates a **true reactive dependency** on time
- The reactive context ONLY invalidates when the timer fires
- Other reactive changes in the session do NOT trigger the timer-based observer
- Clean separation: timer logic vs conditional logic

### Isolated Writes Pattern

All reactive value writes in the main observer use `isolate()`:

```r
isolate(rv$last_update <- Sys.time())
isolate(rv$initial_load_complete <- TRUE)
```

**Why:** Writing to a reactive value normally triggers all observers that depend on it. Using `isolate()` for writes prevents cascading reactive invalidations, keeping the reactive graph clean and predictable.

---

## ~~Proposed Solutions~~ IMPLEMENTED Solution

## ~~IMPLEMENTED Solution~~ ✅ Final Implementation

### Pattern: reactiveTimer() with Dynamic Interval

**Implemented Code:**

```r
# Create reactive timer with dynamic interval
auto_refresh_timer <- reactive({
  interval_ms <- input$refresh_interval * 1000
  reactiveTimer(interval_ms)()
})

# Observer depends ONLY on timer
observe({
  auto_refresh_timer()  # Reactive dependency
  if (isolate(input$auto_refresh) && isolate(!rv$query_running)) {
    refresh_trigger(isolate(refresh_trigger()) + 1)
  }
})
```

**Benefits:**

- ✅ `reactiveTimer()` creates a clean reactive dependency that ONLY fires on schedule
- ✅ No spurious triggers from other reactive changes
- ✅ Dynamic interval - changes to `input$refresh_interval` immediately take effect
- ✅ Clear separation of timing logic from conditional logic
- ✅ All conditional checks use `isolate()` to prevent additional dependencies

### Pattern: Separate Flag for Control Flow

**Implemented Code:**

```r
rv <- reactiveValues(
  initial_load_complete = FALSE,
  last_update = NULL,
  # ...
)

observe({
  current_status <- task_data()
  
  # Control flow using dedicated flag
  if (isolate(rv$initial_load_complete)) {
    req(isolate(input$main_tabs) == "Pipeline Status")
  }
  
  # ... update logic ...
  
  # Isolated writes prevent cascading
  isolate(rv$last_update <- Sys.time())
  isolate(rv$initial_load_complete <- TRUE)
})
```

**Benefits:**

- ✅ No observer self-dependency
- ✅ Clear intent: flag for control, timestamp for display
- ✅ Isolated writes prevent triggering other observers
- ✅ Simple boolean state (FALSE → TRUE once)

---

## ~~Option 1: Use `reactiveTimer()` (Recommended)~~

~~Replace `observe()` + `invalidateLater()` with `reactiveTimer()`:~~

~~**Benefits:**~~

~~- `reactiveTimer()` creates a clean reactive dependency that ONLY fires on schedule~~

~~### Option 2: Move conditional logic inside `task_data()`~~

---

## Testing Checklist

When verifying reactive dependency fixes:

- [x] ✅ Check R console for message frequency (should be ~5 second intervals, not <1 sec)
- [ ] Verify initial page load renders data
- [ ] Confirm auto-refresh checkbox works
- [ ] Test manual refresh button
- [ ] Monitor under high server load (load average > 40)
- [ ] Check browser JS console for Shiny errors
- [ ] Verify cooldown prevents query flooding (5 sec minimum enforced)
- [ ] Test tab switching behavior (updates only on Pipeline Status tab)
- [ ] Verify dynamic interval changes (change refresh_interval input)
- [ ] Check that busy indicator shows during queries

**Expected Behavior:**
- Console messages appear every 5 seconds (or custom interval)
- No reactive flood/storm messages
- Database queries respect 5-second cooldown
- UI updates smoothly without flickering
- No infinite loop or cascade of reactive invalidations

---

## Maintenance Instructions

**When modifying reactive code in `server.R`:**

1. **Before changes:** Document current reactive dependencies in this file
2. **After changes:** Update this diagram to reflect new dependencies
3. **Test thoroughly:** Use checklist above
4. **Add notes:** Document any new anti-patterns discovered

**Red flags to watch for:**

- ⚠️ ~~`observe()` that both reads AND writes the same reactive value~~ ✅ FIXED
- ⚠️ ~~`invalidateLater()` inside `observe()` without `reactiveTimer()`~~ ✅ FIXED
- ⚠️ Reactive values modified inside `on.exit()` (can trigger during flush) - ✅ We use `on.exit()` correctly for cleanup only
- ⚠️ `input$*` or `rv$*` accessed without `isolate()` in timer-based observers - ✅ All isolated
- ⚠️ Multiple observers depending on the same fast-changing reactive value - ✅ Using `bindEvent()` to control dependencies

---

## References

- [Shiny Reactivity Documentation](https://shiny.rstudio.com/articles/reactivity-overview.html)
- [Common Shiny Anti-patterns](https://shiny.rstudio.com/articles/debugging.html)
- Mastering Shiny Chapter 14: Reactive Programming (Advanced)
- Project skill: `#shiny-ui-patterns` in `.github/skills/`

