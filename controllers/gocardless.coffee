LoggedInController = require 'members-area/app/controllers/logged-in'
async = require 'members-area/node_modules/async'

class GoCardlessController extends LoggedInController
  @before 'requireAdmin'
  @before 'saveSettings', only: ['admin']
  @before 'getSubscriptions', only: ['subscriptions', 'bills']

  admin: ->

  subscriptions: ->

  payouts: (done) ->
    @client().payout.index (err, res, body) =>
      @payoutList = JSON.parse body
      done()

  bills: (done) ->
    @client().bill.index (err, res, body) =>
      @billList = JSON.parse body
      for bill in @billList when bill.source_type is 'subscription'
        for subscription in @subscriptionList when subscription.id is bill.source_id
          bill.subscription = subscription
      done()

  getSubscriptions: (done) ->
    @client().subscription.index (err, res, body) =>
      @subscriptionList = JSON.parse body
      done()

  requireAdmin: (done) ->
    unless @req.user and @req.user.can('admin')
      err = new Error "Permission denied"
      err.status = 403
      return done err
    else
      done()

  saveSettings: (done) ->
    if @req.method is 'POST'
      fields = ['appId', 'appSecret', 'merchantId', 'token']
      data = {}
      data[field] = @req.body[field] for field in fields
      data.sandbox = (@req.body.sandbox is 'on')
      gocardless = require('gocardless')(data)
      gocardless.merchant.getSelf (err, response, body) =>
        try
          throw err if err
          body = JSON.parse(body)
          throw new Error(body.error.join(" \n")) if body.error
          @plugin.set data, done
        catch err
          console.dir err
          @errorMessage = err.message || "An error occurred"
          done()
    else
      @data = @plugin.get()
      done()

  client: ->
    @gocardlessClient ||= require('gocardless')(@plugin.get())

module.exports = GoCardlessController
