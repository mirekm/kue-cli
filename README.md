# A simple CLI tool for managing Kue tasks

Kue-cli is a *command line* job management client for Kue.


### Commands
---

#### Stats
Display number of active, complete, delayed, failed and stuck (but active) tasks

`./index.coffee stats`

*Paramaters:*

-t [seconds] — it applies only to stuck-active tasks. Number of seconds between task's last update_at and now() determining the task is stuck

*Example:*

`./index.coffee stats -t 600` displays stats including active tasks not being updated for the last 10 minutes

-

#### Watch
It's a self-refreshing version of **stats** command 

`./index.coffee watch`

-

#### List
List jobs of given status. `limit` to 50 by default.

`./index.coffee list [active|complete|delayed|failed|stuck] [limit]`

*Example:*

`./index.coffee list complete 50` displays last 10 complete tasks 

-

#### Job
Show job with a given id

`./index.coffee job [id]`

*Parameters:*

-i — open job data in REPL

-

### License
---
MIT
