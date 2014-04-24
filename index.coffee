cheerio = require 'members-area/node_modules/cheerio'
encode = require('members-area/node_modules/entities').encodeXML

module.exports =
  initialize: (done) ->
    @app.addRoute 'all', '/admin/gocardless', 'members-area-gocardless#gocardless#admin'
    @app.addRoute 'all', '/admin/gocardless/subscriptions', 'members-area-gocardless#gocardless#subscriptions'
    @app.addRoute 'all', '/admin/gocardless/payouts', 'members-area-gocardless#gocardless#payouts'
    @app.addRoute 'all', '/admin/gocardless/bills', 'members-area-gocardless#gocardless#bills'
    @hook 'navigation_items', @modifyNavigationItems.bind(this)
    @hook 'render-payments-subscription-view', @renderSubscriptionView.bind(this)
    paymentsPlugin = @app.getPlugin("members-area-payments")
    if paymentsPlugin
      SubscriptionController = require "#{paymentsPlugin.path}/controllers/subscription"
      self = this
      setUpGocardlessPayments = (callback) ->
        self.setUpGocardlessPayments(this, callback)
      SubscriptionController.before setUpGocardlessPayments, only: ["view"]

    done()

  setUpGocardlessPayments: (controller, callback) ->
    controller.data.dom ?= controller.loggedInUser.meta.gocardless?.dayOfMonth ? new Date().getDate() + 1
    controller.data.monthly ?= controller.loggedInUser.meta.gocardless?.monthly
    controller.data.initial ?= controller.loggedInUser.meta.gocardless?.initial
    return callback() unless controller.req.method is 'POST' and controller.req.body?.form is "gocardless"
    {dom, monthly, initial} = controller.req.body
    console.log "Charge me £#{initial} up front followed by £#{monthly} per month on the #{dom} day of the month"
    initial = parseFloat initial
    monthly = parseFloat monthly
    dom = parseInt dom, 10

    error = false
    if !isFinite(initial) or initial > 500
      controller.error_initial = "please enter a number of pounds and pence"
      error = true
    if !isFinite(monthly) or monthly > 200
      controller.error_monthly = "please enter a number of pounds and pence"
      error = true
    if !isFinite(dom) or not (0 < dom < 29)
      controller.error_dom = "please pick a day of the month"
      error = true

    return callback() if error

    callback()

  modifyNavigationItems: ({addItem}) ->
    addItem 'admin',
      title: 'GoCardless'
      id: 'members-area-gocardless-admin'
      href: '/admin/gocardless'
      permissions: ['admin']
      priority: 53

  renderSubscriptionView: (options) ->
    {controller, html} = options
    $ = cheerio.load(html)
    checked = ""

    paidUntil = controller.req.models.Payment.getUserPaidUntil controller.loggedInUser
    counter = new Date()
    counter.setHours(0)
    counter.setMinutes(0)
    monthsOverdue = 0
    while +counter > +paidUntil and monthsOverdue < 6
      monthsOverdue++
      counter.setMonth(counter.getMonth() - 1)

    $newNode = $ """
      <h3>GoCardless</h3>
      <p>
        <a href="https://gocardless.com/?r=Z65JVARP&utm_source=website&utm_medium=copy_paste&utm_campaign=referral_scheme_50">GoCardless</a>
        are the next cheapest way to send us money after standing orders/cash.
        They charge just 1% per transaction (e.g. 20p for every £20) and so are
        very affordable.
      </p>
      <p class="text-info">GoCardless collect money via Direct Debit, and so your payments are covered by the Direct Debit Guarantee.</p>
      <p>To get started, just enter your preferred monthly payment amount below:</p>
      <form method="POST" action="">
        <input type="hidden" name="form" value="gocardless">
        <table style="width:auto" class="table table-bordered">
          <tbody>
            <tr>
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
                <input type="text" name="monthly" value="#{encode controller.data.monthly ? "30"}" id="gocardless_monthly"><br>
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
                  <input type="text" name="initial" value="#{encode controller.data.initial ? "0"}" id="gocardless_initial"><br>
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
    options.html = $.html()
    return
