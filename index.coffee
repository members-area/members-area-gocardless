cheerio = require 'members-area/node_modules/cheerio'

module.exports =
  initialize: (done) ->
    @app.addRoute 'all', '/admin/gocardless', 'members-area-gocardless#gocardless#admin'
    @app.addRoute 'all', '/admin/gocardless/subscriptions', 'members-area-gocardless#gocardless#subscriptions'
    @app.addRoute 'all', '/admin/gocardless/payouts', 'members-area-gocardless#gocardless#payouts'
    @app.addRoute 'all', '/admin/gocardless/bills', 'members-area-gocardless#gocardless#bills'
    @hook 'navigation_items', @modifyNavigationItems.bind(this)
    @hook 'render-payments-subscription-view', @renderSubscriptionView.bind(this)

    done()

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
      <form method="POST" action="/subscription/gocardless">
        <input type="hidden" name="form" value="gocardless">
        <table style="width:auto" class="table table-bordered">
          <tbody>
            <tr>
              <th>
                First monthly payment<br>
                <small>Payments will come out on or around this day each month.</small>
                <br>
                <small>Must be between tomorrow and one month's time.</small>
              </th>
              <td>
                <input type="text" name="date" value="2014-05-13"><br>
                <small>(YYYY-MM-DD)</small>
              </td>
            </tr>
            <tr>
              <th>Monthly amount, £</th>
              <td>
                <input type="text" name="monthly" value="30" id="gocardless_monthly"><br>
                <small>(Including the GoCardless fee, this will be £<strong id="gocardless_monthly_inc">30.30</strong>)</small>
              </td>
            </tr>
            <tr>
              <th>
                Initial fee, £<br><small>One-off donation, completely optional.</small><br>
                <small>This will be taken out of your account soon.</small>
              </th>
              <td>
                <input type="text" name="initial" value="0.00" id="gocardless_initial"><br>
                <small>(Including the GoCardless fee, this will be £<strong id="gocardless_initial_inc">0.00</strong>)</small>
              </td>
            </tr>
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
          var unmodified = true;

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
