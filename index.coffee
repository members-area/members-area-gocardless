module.exports =
  initialize: (done) ->
    @app.addRoute 'all', '/admin/gocardless', 'members-area-gocardless#gocardless#admin'
    @hook 'navigation_items', @modifyNavigationItems.bind(this)

    done()

  modifyNavigationItems: ({addItem}) ->
    addItem 'admin',
      title: 'GoCardless'
      id: 'members-area-gocardless-gocardless-admin'
      href: '/admin/gocardless'
      permissions: ['admin']
      priority: 53
