# A simple CLI tool for managing Kue tasks

Kue-cli is a *command line* job management client for Kue.

## Installation

`npm install kue-cli`

---

## Commands


#### stats
Display number of active, complete, delayed, failed and stuck (but active) tasks

`./index.coffee stats`

*Paramaters:*

-t [seconds] — it applies only to stuck-active tasks. Number of seconds between task's last update_at and now() determining the task is stuck

*Example:*

`./index.coffee stats -t 600` displays stats including active tasks not being updated for the last 10 minutes

-

#### watch
It's a self-refreshing version of **stats** command 

`./index.coffee watch`

-

#### list
List jobs of given status. `limit` to 50 by default.

`./index.coffee list [active|complete|delayed|failed|stuck] [limit]`

*Example:*

`./index.coffee list complete 50` displays last 10 complete tasks 

-

#### job
Show job with a given id

`./index.coffee job [id]`

*Parameters:*

-i — open job data in REPL

*Examples:*

`./index.coffee job 5031` outputs job #5031

`./index.coffee job 3501 -i` opens job #3501 in interactive REPL

-

### Bugs & progress
---

https://overv.io/workspace/mirekm/adorable-salamander/

### License
---
MIT
