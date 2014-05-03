LoggedInController = require 'members-area/app/controllers/logged-in'
async = require 'members-area/node_modules/async'
_ = require 'members-area/node_modules/underscore'

class GoCardlessController extends LoggedInController
  @callbackTimeout: 240000
  @before 'requireAdmin'
  @before 'setActiveNagivationId'
  @before 'saveSettings', only: ['admin']
  @before 'cancelPreauth', only: ['preauths']
  @before 'getUsers', only: ['preauths', 'bills', 'subscriptions']
  @before 'getSubscriptions', only: ['subscriptions', 'bills']
  @before 'getPreauths', only: ['preauths', 'bills']
  @before 'getBills', only: ['bills']
  @before 'reprocess', only: ['bills']
  @before 'updateSubscriptions', only: ['subscriptions']

  admin: ->

  subscriptions: ->

  preauths: ->

  do_preauths: (done) ->
    return @redirectTo "/admin/gocardless/preauths/dr" if @req.method isnt 'POST' or @req.body.confirm isnt 'confirm'
    @plugin.createNewBillsWithModels @req.models, dryRun: false, (@err, @results) =>
      done()

  dr_preauths: (done) ->
    @plugin.createNewBillsWithModels @req.models, dryRun: true, (@err, @results) =>
      @dryRun = true
      @template = 'do_preauths'
      done()

  payouts: (done) ->
    @client().payout.index (err, res, body) =>
      @payoutList = JSON.parse body
      done()

  bills: ->

  cancelPreauth: (done) ->
    return done() unless @req.method is 'POST' and @req.body.cancel
    @client().preAuthorization.cancel {id:@req.body.cancel}, (err, res, body) =>
      try
        body = JSON.parse body if typeof body is 'string'
        throw new Error(body.error.join(" \n")) if body.error
        console.log "Cancelled preauth #{@req.body.cancel}"
      catch e
        err ?= e
      done err

  getUsers: (done) ->
    @req.models.User.all (err, @users) =>
      @usersById = {}
      @usersById[user.id] = user for user in @users
      done(err)

  getBills: (done) ->
    @client().bill.index (err, res, body) =>
      try
        body = JSON.parse body if typeof body is 'string'
        throw new Error(body.error.join(" \n")) if body.error
        @billList = body
        for bill in @billList when bill.source_type is 'subscription'
          for subscription in @subscriptionList when subscription.id is bill.source_id
            bill.subscription = subscription
        for bill in @billList when bill.source_type is 'pre_authorization'
          for preauth in @preauthList when preauth.id is bill.source_id
            bill.preauth = preauth
      catch e
        err ?= e
      done()

  getSubscriptions: (done) ->
    @client().subscription.index (err, res, body) =>
      try
        body = JSON.parse body if typeof body is 'string'
        throw new Error(body.error.join(" \n")) if body.error
        @subscriptionList = body
      catch e
        err ?= e
      done(err)

  updateSubscriptions: (done) ->
    return done() unless @req.method is 'POST' and @req.body.update is 'update'
    @update = true
    subscriptionByUserId = {}
    subscriptionByUserId[parseInt(s.name.substr(1), 10)] = s for s in @subscriptionList when s.status is 'active'
    checkUser = (user, next) ->
      s = subscriptionByUserId[user.id]
      gc = _.clone user.meta.gocardless ? {}
      update = ->
        user.setMeta gocardless: gc
        user.save next
      if s
        s.user = user
        gc.subscription_resource_id = s.id
        update()
      else
        if gc.subscription_resource_id
          delete gc.subscription_resource_id
          update()
        else
          next()
    async.eachSeries @users, checkUser, done

  getPreauths: (done) ->
    @client().preAuthorization.index (err, res, body) =>
      try
        body = JSON.parse body if typeof body is 'string'
        throw new Error(body.error.join(" \n")) if body.error
        @preauthList = body
        @preauthList.filter((p) -> p.name.match /^M[0-9]+$/).forEach (preauth) =>
          preauth.user = @usersById[parseInt(preauth.name.substr(1), 10)]
        preauthById = {}
        preauthById[p.id] = p for p in @preauthList
        relevantUsers = @users.filter((user) -> user.meta.gocardless?.resource_id)
        checkPreauth = (user, next) =>
          preauth = preauthById[user.meta.gocardless.resource_id]
          if !preauth or preauth.status isnt 'active'
            console.error "REMOVING USER #{user.id}'s gocardless resource_id"
            gocardless = user.meta.gocardless
            delete gocardless.resource_id
            delete gocardless.paidInitial
            user.setMeta gocardless: gocardless
            user.save next
          else
            next()
        async.eachSeries relevantUsers, checkPreauth, done
        return
      catch e
        err ?= e
      done(err)

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
    for bill in @billList when (matches = (bill.subscription ? bill.preauth ? bill).name?.match regex)
      userId = parseInt matches[1], 10
      paymentsByUser[userId] ?= []
      paymentsByUser[userId].push bill

    async.map _.pairs(paymentsByUser), @_processUserBills.bind(this), (err, groupedNewRecords) ->
      done err

  _processUserBills: ([userId, bills], done) ->
    bills.sort (a, b) -> Date.parse(a.created_at) - Date.parse(b.created_at)
    return done() unless bills.length
    @req.models.User.get userId, (err, user) =>
      console.error err if err
      if !user
        console.error "Could not find user '#{userId}'"
      return done null, null if err or !user
      @req.models.Payment.find().run (err, payments) =>
        console.error err if err
        if !payments
          console.error "Could not load payments for '#{userId}'"
        return done null, null if err or !payments
        nextPaymentDate = user.getPaidUntil new Date Date.parse bills[0].created_at

        updatedRecords = []
        newRecords = []

        for bill in bills
          existingPayment = null
          existingPayment = p for p in payments when p.meta.gocardlessBillId is bill.id

          status = @mapStatus(bill.status)
          amount = Math.round((parseFloat(bill.amount) - parseFloat(bill.gocardless_fees)) * 100)
          periodCount = 1

          if existingPayment
            if existingPayment.status isnt status or existingPayment.amount isnt amount or existingPayment.user_id isnt userId
              if existingPayment.status isnt status
                existingPayment.status = status
                if bill.status in ['failed', 'cancelled']
                  # Deactiveate bill
                  existingPayment.include = false
                  # Decrease paidUntil
                  nextPaymentDate = new Date(+nextPaymentDate)
                  nextPaymentDate.setMonth(nextPaymentDate.getMonth()-existingPayment.period_count)
              existingPayment.amount = amount
              existingPayment.user_id = userId
              updatedRecords.push existingPayment
          else
            if user.meta.gocardless
              gocardless = user.meta.gocardless
              if gocardless.paidInitial? and !gocardless.paidInitial and gocardless.initial > 0 and gocardless.monthly > 0
                periodCount += Math.round(gocardless.initial / gocardless.monthly)
              gocardless.paidInitial = true
              user.setMeta gocardless: gocardless
            payment =
              user_id: userId
              transaction_id: null
              type: 'GC'
              amount: amount
              status: status
              include: bill.status not in ['failed', 'cancelled']
              when: new Date Date.parse bill.created_at
              period_from: nextPaymentDate
              period_count: periodCount
              meta:
                gocardlessBillId: bill.id
            newRecords.push payment
            if payment.include
              nextPaymentDate = new Date(+nextPaymentDate)
              nextPaymentDate.setMonth(nextPaymentDate.getMonth()+periodCount)
        user.paidUntil = nextPaymentDate
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
