encode = require('members-area/node_modules/entities').encodeXML

module.exports =
  initialize: (done) ->
    @app.addRoute 'all', '/admin/gocardless', 'members-area-gocardless#gocardless#admin'
    @app.addRoute 'all', '/admin/gocardless/subscriptions', 'members-area-gocardless#gocardless#subscriptions'
    @app.addRoute 'all', '/admin/gocardless/payouts', 'members-area-gocardless#gocardless#payouts'
    @app.addRoute 'all', '/admin/gocardless/bills', 'members-area-gocardless#gocardless#bills'
    @app.addRoute 'all', '/admin/gocardless/preauths', 'members-area-gocardless#gocardless#preauths'
    @hook 'navigation_items', @modifyNavigationItems.bind(this)
    @hook 'render-payments-subscription-view', @renderSubscriptionView.bind(this)
    paymentsPlugin = @app.getPlugin("members-area-payments")
    if paymentsPlugin
      SubscriptionController = require "#{paymentsPlugin.path}/controllers/subscription"
      self = this
      wrapSelf = (fn) ->
        (callback) ->
          fn.call self, this, callback
      SubscriptionController.before wrapSelf(@gocardlessPaymentsCallback), only: ["view"]
      SubscriptionController.before wrapSelf(@setUpGocardlessPayments), only: ["view"]

    done()

  gocardlessPaymentsCallback: (controller, callback) ->
    loggedInUser = controller.loggedInUser

    req = controller.req
    if req.method is 'GET' and req.query.signature and req.query.resource_uri and req.query.resource_id and req.query.resource_type is "pre_authorization" and req.query.state is String(loggedInUser.id) and loggedInUser.meta.gocardless
      # This looks like a valid gocardless callback!
      gocardlessClient = require('gocardless')(@get())
      gocardlessClient.confirmResource req.query, (err, request, body) =>
        return callback err if err
        # SUCCESS!
        gocardless = loggedInUser.meta.gocardless ? {}
        gocardless.resource_id = req.query.resource_id
        loggedInUser.setMeta gocardless: gocardless
        loggedInUser.save =>
          controller.redirectTo "/subscription"
          callback()
    else
      return callback()

  setUpGocardlessPayments: (controller, callback) ->
    loggedInUser = controller.loggedInUser
    controller.data.dom ?= loggedInUser.meta.gocardless?.dayOfMonth ? new Date().getDate() + 1
    controller.data.monthly ?= loggedInUser.meta.gocardless?.monthly
    controller.data.initial ?= loggedInUser.meta.gocardless?.initial
    return callback() unless controller.req.method is 'POST' and controller.req.body?.form is "gocardless"
    {dom, monthly, initial} = controller.req.body
    console.log "Charge me £#{initial} up front followed by £#{monthly} per month on the #{dom} day of the month"
    initial = parseFloat initial
    monthly = parseFloat monthly
    dom = parseInt dom, 10

    min_amount = @get('min_amount') ? 5
    error = false
    if !isFinite(initial) or initial > 500
      controller.error_initial = "Please enter a sensible number of pounds and pence"
      error = true
    if !isFinite(monthly) or monthly > 200
      controller.error_monthly = "Please enter a sensible number of pounds and pence"
      error = true
    if monthly < min_amount
      controller.error_monthly = "Minimum monthly payment is £#{min_amount.toFixed(2)}"
      error = true
    if !isFinite(dom) or not (0 < dom < 29)
      controller.error_dom = "Please pick a day of the month"
      error = true

    return callback() if error
    initial = initial.toFixed(2)
    monthly = monthly.toFixed(2)

    gocardless = loggedInUser.meta.gocardless ? {}
    gocardless.initial = initial
    gocardless.monthly = monthly
    gocardless.dayOfMonth = dom
    loggedInUser.setMeta gocardless: gocardless
    loggedInUser.save =>
      max = @get('max_amount') ? 100
      if max < initial + monthly
        max = (initial + monthly) * 1.1

      # Guess at some stuff to prefill for them
      tmp = loggedInUser.fullname.split(" ")
      firstName = tmp[0]
      lastName = tmp[tmp.length-1]
      address = loggedInUser.address
      tmp = address.match /[A-Z]{2}[0-9]{1,2}\s*[0-9][A-Z]{2}/i
      if tmp
        postcode = tmp[0].toUpperCase()
        address = address.replace(tmp[0], "")
      tmp = address.split /[\n\r,]/
      tmp = tmp.filter (a) -> a.replace(/\s+/g, "").length > 0
      tmp = tmp.filter (a) -> !a.match /^(hants|hampshire)$/
      for potentialTown, i in tmp
        t = potentialTown.replace /[^a-z]/gi, ""
        if t.match /^(southampton|soton|eastleigh|chandlersford|winchester|northbaddesley|havant|portsmouth|bournemouth|poole|bognorregis|romsey|lyndhurst|eye|warsash|lymington)$/i
          town = potentialTown
          tmp.splice i, 1
          break
      town ?= "Southampton"
      if tmp.length > 1
        address2 = tmp.pop()
      address1 = tmp.join(", ")

      gocardlessClient = require('gocardless')(@get())
      url = gocardlessClient.preAuthorization.newUrl
        max_amount: max
        interval_length: 1
        interval_unit: 'month'
        name: "M#{controller.res.locals.pad(loggedInUser.id, 6)}"
        description: "#{controller.app.siteSetting.meta.settings.name ? "Members Area"} subscription"
        redirect_uri: "#{controller.baseURL()}/subscription"
        cancel_uri: "#{controller.baseURL()}/subscription"
        state: loggedInUser.id
        user:
          first_name: firstName
          last_name: lastName
          email: loggedInUser.email
          account_name: loggedInUser.fullname
          billing_address1: address1
          billing_address2: address2
          billing_town: town
          billing_postcode: postcode
      controller.redirectTo url
      callback()

  modifyNavigationItems: ({addItem}) ->
    addItem 'admin',
      title: 'GoCardless'
      id: 'members-area-gocardless-admin'
      href: '/admin/gocardless'
      permissions: ['admin']
      priority: 53

  renderSubscriptionView: (options) ->
    {controller, $} = options
    checked = ""

    paidUntil = controller.loggedInUser.paidUntil
    counter = new Date()
    counter.setHours(0)
    counter.setMinutes(0)
    monthsOverdue = 0
    while +counter > +paidUntil and monthsOverdue < 6
      monthsOverdue++
      counter.setMonth(counter.getMonth() - 1)

    isSetUp = controller.loggedInUser.meta.gocardless?.resource_id?
    hideIfSetUp = " style='display:none'" if isSetUp
    hideIfSetUp ?= ""
    $newNode = $ """
      <h3>GoCardless</h3>
      <p>
        <a href="https://gocardless.com/?r=Z65JVARP&utm_source=website&utm_medium=copy_paste&utm_campaign=referral_scheme_50">GoCardless</a>
        are the next cheapest way to send us money after standing orders/cash.
        They charge just 1% per transaction (e.g. 20p for every £20) and so are
        very affordable.
      </p>
      <p class="text-info">GoCardless collect money via Direct Debit, and so your payments are covered by the Direct Debit Guarantee.</p>
      """ + (if isSetUp then """
      <p class="text-success">Thank you for setting up a GoCardless subscription; you can edit the amount below.</p>
      """ else """
      <p>To get started, just enter your preferred monthly payment amount below:</p>
      """) + """
      <form method="POST" action="">
        <input type="hidden" name="form" value="gocardless">
        <table style="width:auto" class="table table-bordered">
          <tbody>
            <tr#{hideIfSetUp}>
              <th>
                Day of month<br>
                <small>We'll try and make sure payments come out <br />on or around this day each month.</small>
              </th>
              <td>
                <select name="dom">
                  #{("<option value='#{i}'#{if String(i) is String(controller.data.dom) then " selected='selected'" else ""}>#{i}</option>" for i in [1..28]).join("\n")}
                </select>
                #{if controller.error_dom then "<p class='text-error'>#{encode controller.error_dom}</p>" else ""}
              </td>
            </tr>
            <tr>
              <th>Monthly amount, £</th>
              <td>
                <input type="text" name="monthly" value="#{encode String(controller.data.monthly) ? "30"}" id="gocardless_monthly"><br>
                <small>(Including the GoCardless fee, this will be £<strong id="gocardless_monthly_inc">?</strong>)</small>
                #{if controller.error_monthly then "<p class='text-error'>#{encode controller.error_monthly}</p>" else ""}
              </td>
            </tr>
            """ + (unless controller.loggedInUser.meta.gocardless?.paidInitial then """
              <tr>
                <th>
                  Initial fee, £<br><small>One-off donation, completely optional.</small><br>
                  <small>This will be taken out of your account soon.</small>
                </th>
                <td>
                  <input type="text" name="initial" value="#{encode String(controller.data.initial) ? "0"}" id="gocardless_initial"><br>
                  <small>(Including the GoCardless fee, this will be £<strong id="gocardless_initial_inc">?</strong>)</small>
                  #{if controller.error_initial then "<p class='text-error'>#{encode controller.error_initial}</p>" else ""}
                </td>
              </tr>
              """ else "") +
            """
          </tbody>
        </table>
        <button type="submit" class="btn btn-success btn-large">Set up payments</button>
      </form>
      <script type="text/javascript">
        (function() {
          var gocardless_monthly = document.getElementById('gocardless_monthly');
          var gocardless_initial = document.getElementById('gocardless_initial');
          var gocardless_monthly_inc = document.getElementById('gocardless_monthly_inc');
          var gocardless_initial_inc = document.getElementById('gocardless_initial_inc');
          var unmodified = #{if controller.req.body?.initial then "false" else "true"};

          gocardless_monthly.addEventListener('change', update_gocardless_monthly_inc, false);
          gocardless_monthly.addEventListener('keyup', update_gocardless_monthly_inc, false);
          gocardless_initial.addEventListener('change', make_modified, false);
          gocardless_initial.addEventListener('change', update_gocardless_initial_inc, false);
          gocardless_initial.addEventListener('keyup', update_gocardless_initial_inc, false);

          function make_modified() {
            unmodified = false;
          }

          function update_gocardless_monthly_inc() {
            if (unmodified) {
              var v = parseFloat(gocardless_monthly.value);
              if (!isNaN(v)) {
                gocardless_initial.value = (v * #{monthsOverdue}).toFixed(2);
                update_gocardless_initial_inc();
              }
            }
            return update_gocardless_a(gocardless_monthly, gocardless_monthly_inc);
          }

          function update_gocardless_initial_inc(e) {
            return update_gocardless_a(gocardless_initial, gocardless_initial_inc);
          }

          function update_gocardless_a(amount, after) {
            var amount = parseFloat(amount.value);
            if (!isNaN(amount)) {
              amount = 100/99 * amount;
              after.textContent = amount.toFixed(2);
            }
          }

          update_gocardless_monthly_inc();
          update_gocardless_initial_inc();
        })();
      </script>

      """
    $(".main").append($newNode)
    return
