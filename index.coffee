#!/usr/bin/env coffee


_ = require 'underscore'
async = require 'async'
colors = require 'colors/safe'
columnify = require 'columnify'
cli = require 'commander'
kue = require 'kue'
redis = require 'redis'

config = require './config'

redisClient = redis.createClient config.REDIS_DB_URL


class Watcher

    defaults:
        stream: process.stderr
        interval: 20
        columnify:
            columns: ['STATUS', 'COUNT']
            config: COUNT: align: 'right'

    constructor: (options={}) ->
         @options = _.extend @defaults, options
         @options.queue = kue.createQueue redis: config.REDIS_DB_URL

    getActiveCount: (callback) =>
        @options.queue.inactiveCount (error, value) ->
            callback error, colors.blue value

    getCompleteCount: (callback) =>
        @options.queue.completeCount (error, value) ->
            callback error, colors.green value

    getDelayedCount: (callback) =>
        @options.queue.delayedCount  (error, value) ->
            callback error, colors.yellow value

    getFailedCount: (callback) =>
        @options.queue.failedCount  (error, value) ->
            callback error, colors.red value

    getStats: (callback) ->
        async.parallel
            Active: @getActiveCount
            Complete: @getCompleteCount
            Delayed: @getDelayedCount
            Failed: @getFailedCount
        , callback

    watch: () ->
        @dx = 0
        @dy = 0
        @render()
        setInterval () =>
            @render()
        , @options.interval

    render: (callback) ->
        @getStats (error, stats) =>
            if not error
                str = columnify stats, @options.columnify
                str += '\n'
                if @lastDraw isnt str
                    @options.stream.moveCursor @dx, @dy
                    @options.stream.write str
                    @lastDraw = str
                    @dy = -5
                callback and callback()
            else
                callback and callback error


cli
    .version '0.0.1'

cli
    .command 'watch'
    .description 'watch active, complete, delayed and failed Kue tasks'
    .action (env, options) ->
        watcher = new Watcher
            client: redisClient
        watcher.watch()

cli
    .command 'stats'
    .description 'show active, stuck and inactive Kue tasks'
    .action (env, options) ->
        watcher = new Watcher
            client: redisClient
        watcher.render () ->
            process.exit 1

cli.parse process.argv
