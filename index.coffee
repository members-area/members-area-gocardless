module.exports =
  initialize: (done) ->
    @app.addRoute 'all', '/admin/gocardless', 'members-area-gocardless#gocardless#admin'
    @app.addRoute 'all', '/admin/gocardless/subscriptions', 'members-area-gocardless#gocardless#subscriptions'
    @app.addRoute 'all', '/admin/gocardless/payouts', 'members-area-gocardless#gocardless#payouts'
    @app.addRoute 'all', '/admin/gocardless/bills', 'members-area-gocardless#gocardless#bills'
    @hook 'navigation_items', @modifyNavigationItems.bind(this)

    done()

  modifyNavigationItems: ({addItem}) ->
    addItem 'admin',
      title: 'GoCardless'
      id: 'members-area-gocardless-admin'
      href: '/admin/gocardless'
      permissions: ['admin']
      priority: 53
