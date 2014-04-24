LoggedInController = require 'members-area/app/controllers/logged-in'
async = require 'members-area/node_modules/async'
_ = require 'members-area/node_modules/underscore'

class GoCardlessController extends LoggedInController
  @before 'requireAdmin'
  @before 'setActiveNagivationId'
  @before 'saveSettings', only: ['admin']
  @before 'getSubscriptions', only: ['subscriptions', 'bills']
  @before 'getBills', only: ['bills']
  @before 'reprocess', only: ['bills']

  admin: ->

  subscriptions: ->

  payouts: (done) ->
    @client().payout.index (err, res, body) =>
      @payoutList = JSON.parse body
      done()

  bills: ->

  getBills: (done) ->
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
          @successMessage = "We checked with GoCardless and you've successfully identified as merchant #{data.merchantId} :)"
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

  setActiveNagivationId: ->
    @activeNavigationId = 'members-area-gocardless-admin'

  # This method prevents multiple requests from doing multiple reconciliations at the same time.
  reprocess: (done) ->
    return done() unless @req.method is 'POST' and @req.body.reprocess
    doIt = =>
      if reconciliationInProgress
        setTimeout doIt, 5
      else
        reconciliationInProgress = true
        @_reprocess ->
          reconciliationInProgress = false
          done.apply this, arguments
    doIt()

  _reprocess: (done) ->
    paymentsByUser = {}
    regex = /^M(0[0-9]+)$/
    for bill in @billList when (matches = bill.subscription?.name?.match regex)
      userId = parseInt matches[1], 10
      paymentsByUser[userId] ?= []
      paymentsByUser[userId].push bill

    async.map _.pairs(paymentsByUser), @_processUserBills.bind(this), (err, groupedNewRecords) ->
      done err

  _processUserBills: ([userId, bills], done) ->
    bills.sort (a, b) -> Date.parse(a.created_at) - Date.parse(b.created_at)
    return done() unless bills.length
    @req.models.User.get userId, (err, user) =>
      if !user
        console.error "Could not find user '#{userId}'"
      return done null, null if err or !user
      @req.models.Payment.find().run (err, payments) =>
        nextPaymentDate = @req.models.Payment.getUserPaidUntil user, new Date Date.parse bills[0].created_at

        updatedRecords = []
        newRecords = []

        for bill in bills
          existingPayment = p for p in payments when p.meta.gocardlessBillId is bill.id
          if existingPayment
            if existingPayment.status != @mapStatus bill.status
              existingPayment.status = @mapStatus bill.status
              if bill.status in ['failed', 'cancelled']
                # Deactiveate bill
                existingPayment.include = false
              updatedRecords.push existingPayment
          else
            payment =
              user_id: userId
              transaction_id: null
              type: 'GC'
              amount: parseInt(parseFloat(bill.amount * 100), 10)
              status: @mapStatus bill.status
              include: bill.status not in ['failed', 'cancelled']
              when: new Date Date.parse bill.created_at
              period_from: nextPaymentDate
              period_count: 1
              meta:
                gocardlessBillId: bill.id
            newRecords.push payment
            nextPaymentDate = new Date(+nextPaymentDate)
            nextPaymentDate.setMonth(nextPaymentDate.getMonth()+1)
        user.setMeta paidUntil: nextPaymentDate
        async.series
          updatePayments: (done) => async.eachSeries updatedRecords, ((r, done) -> r.save done), done
          createPayments: (done) => @req.models.Payment.create newRecords, done
          savePaidUntil: (done) => user.save done
        , (err) =>
          console.dir err if err
          done err, newRecords

  mapStatus: (status) ->
    # Takes a gocardless status and translates into a members area status
    map =
      'paid': 'paid'
      'failed': 'failed'
      'cancelled': 'cancelled'
      'pending': 'pending'
      'withdrawn': 'paid'
    return map[status] ? status

 module.exports = GoCardlessController
