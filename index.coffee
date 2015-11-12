#!/usr/bin/env coffee


_ = require 'underscore'
async = require 'async'
highlight =  require 'ansi-highlight'
colors = require 'colors/safe'
columnify = require 'columnify'
cli = require 'commander'
kue = require 'kue'
moment = require 'moment'
redis = require 'redis'
repl = require 'repl'
stream = require 'stream'

config = require './config'

redisClient = redis.createClient config.REDIS_DB_URL


class Renderer

    defaults: () ->
        stream: process.stdout

    constructor: (options={}) ->
         @options = _.extend _.result(@, 'defaults'), options

    render: (str) ->
        if @lastDraw isnt str
            @options.stream.moveCursor @dx, @dy
            @options.stream.clearLine()
            @options.stream.write str
            @lastDraw = str
            @dy = - str.split('\n').length + 1


class KueCliRenderer extends Renderer

    _formatStats: (stats) ->
        duration = moment.duration(@options.stuckDelta).humanize()
        str = columnify stats, @options.columnify
        str += '\n'
        str += "(for longer than #{duration} in active state)\n"
        str

    defaults: () ->
        _.extend super,
            columnify:
                columns: ['STATUS', 'COUNT']
                config: COUNT: align: 'right'

    renderStats: (stats) ->
        @render @_formatStats stats


class KueApi

    defaults:
        stuckDelta: 5000
        min: 0
        max: 50

    _limitIds: (ids) ->
        ids[@options.min..@options.max]

    constructor: (options={}) ->
         @options = _.extend @defaults, options
         @options.queue = kue.createQueue redis: config.REDIS_DB_URL

    # Counters
    # ------------------------------------------------
    getActiveCount: (callback) =>
        @options.queue.inactiveCount (error, value) ->
            callback error, colors.blue value

    getCompleteCount: (callback) =>
        @options.queue.completeCount (error, value) ->
            callback error, colors.green value

    getDelayedCount: (callback) =>
        @options.queue.delayedCount (error, value) ->
            callback error, colors.yellow value

    getFailedCount: (callback) =>
        @options.queue.failedCount  (error, value) ->
            if +value > 0
                value = colors.red value
            callback error, value

    getStuckActiveCount: (callback) =>
        @getStuckActive (error, jobs) =>
            value = jobs?.length or 0
            if +value > 0
                value = colors.red value
            callback null, value

    # Jobs
    # ------------------------------------------------
    get: (id, callback) ->
        kue.Job.get id, callback

    list: (state, callback) ->
        @getRangeByState state, @options.min, @options.max, callback

    drop: (state, callback) ->
        @getRangeByState state, 0, -1, (error, jobs) ->
            async.reduce jobs, 0, (memo, job, next) ->
                job.remove (error) ->
                    next null, (if not error then memo + 1 else memo)
            , callback

    getRangeByState: (state, min, max, callback) ->
        if state is 'stuck'
            @getStuckActive callback
        else
            kue.Job.rangeByState state, min, max, 'asc', callback

    getStuckActive: (callback) ->
        @options.queue.active (error, ids) =>
            async.map ids, (id, next) =>
                kue.Job.get id, (error, job) =>
                    lastUpdate = +Date.now() - +job.updated_at
                    stuck = lastUpdate > @options.stuckDelta
                    next error, if stuck then job else null
            , (error, results) ->
                if not error
                    results = _.filter results, (job) -> job
                callback and callback error, results

    # Helpers
    # -------------------------------------------------
    getStats: (callback) ->
        async.parallel
            Active: @getActiveCount
            Complete: @getCompleteCount
            Delayed: @getDelayedCount
            Failed: @getFailedCount
            'Stuck Active': @getStuckActiveCount
        , callback


options =
    watchInterval: 200

cli
    .version '0.0.3'

cli
    .command 'watch'
    .option("-t, --time [seconds]", "Time difference between last updated_at and Date.now() determining that the task is stuck", 60)
    .description 'watch active, complete, delayed and failed Kue tasks'
    .action (options) ->
        stuckDelta = options.time * 1000
        renderer = new KueCliRenderer
            stuckDelta: stuckDelta
        kueCli = new KueApi
            client: redisClient
            stuckDelta: stuckDelta
        setInterval () =>
            kueCli.getStats (error, stats) =>
                if error
                    process.exit 0
                else
                    renderer.renderStats stats
        , options.watchInterval

cli
    .command 'stats'
    .option("-t, --time [seconds]", "Time difference between last updated_at and Date.now() determining that the task is stuck", 60)
    .description 'show active, complete, delayed, failed and stuck-active tasks'
    .action (options) ->
        stuckDelta = options.time * 1000
        renderer = new KueCliRenderer
            stuckDelta: stuckDelta
        kueCli = new KueApi
            client: redisClient
            stuckDelta: stuckDelta
        kueCli.getStats (error, stats) =>
            if error
                console.log error
                process.exit 0
            else
                renderer.renderStats stats
                process.exit 1

cli
    .command 'state [state] [number]'
    .option("-t, --time [seconds]", "Time difference between last updated_at and Date.now() determining that the task is stuck", 60)
    .description 'list jobs by state: active, complete, delayed, failed, stuck'
    .action (state, number, cmdOptions) ->
        if not state
            state = 'complete'
        renderer = new KueCliRenderer
        stuckDelta = cmdOptions.time * 1000
        options =
            client: redisClient
            stuckDelta: stuckDelta
        if +number > 0
            options.max = number - 1
        kueCli = new KueApi options
        kueCli.list state, (error, jobs) =>
            jobs = _.map jobs, (job) ->
                duration = job.duration
                'job id': job.id
                'worker id': job.workerId
                'created at': moment(new Date(+job.created_at)).fromNow()
                'updated at': moment(new Date(+job.updated_at)).fromNow()
                failed: if job.failed_at then colors.red(new Date(+job.failed_at)) else colors.green(duration)
            str = columnify jobs,
                columns: ['job id', 'worker id', 'created at', 'updated at', 'failed']
                columnSplitter: colors.grey ' | '
            renderer.render "#{str}\n"
            process.exit 1

cli
    .command 'job [id]'
    .option("-i, --interactive", "Portal yourself to node REPL")
    .description 'show job details'
    .action (id, cmdOptions) ->
        renderer = new KueCliRenderer
        if not id
            renderer.render 'No job id provided. Exiting.'
            process.exit 1
        else
            options =
                client: redisClient
            kueCli = new KueApi options
            kueCli.get +id, (error, job) =>
                str = highlight JSON.stringify(job, null, 4)
                if cmdOptions.interactive
                    console.log 'Entering interactive mode. Type `job` to inspect job\'s fields.'
                    id = colors.bold job.id
                    jobRepl = repl.start
                        prompt: "Job ##{id}> "
                    jobRepl.context.job = job
                else
                    renderer.render str + '\n'
                    process.exit 1

cli
    .command 'drop [state]'
    .option("-t, --time [seconds]", "(Stuck jobs only) time difference between last updated_at and Date.now() determining that the task is stuck", 60)
    .description 'drop jobs of a given state.'
    .action (state, cmdOptions) ->
        if not state
            state = 'stuck'
        renderer = new KueCliRenderer
        options =
            client: redisClient
            stuckDelta: cmdOptions.time * 1000
        kueCli = new KueApi options
        kueCli.drop state, (error, count) ->
            if error
                renderer.render 'Errors removing jobs: ' + error + '\n'
            else
                renderer.render "#{count} #{state} jobs removed successfully.\n"
            process.exit 1


cli.parse process.argv
