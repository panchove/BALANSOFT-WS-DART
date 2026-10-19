/* Sesión del panel administrativo (login/registro/logout de proveedor). */
(function () {
  var STORE = 'balansoft_panel';

  function login(email, password) {
    return window.balansoftApi('/panel/login', {
      method: 'POST',
      body: { email: email, password: password },
      auth: false,
    });
  }

  function saveSession(payload) {
    localStorage.setItem('balansoft_panel_token', payload.access_token);
    localStorage.setItem(
      'balansoft_panel_user',
      JSON.stringify(payload.user || {})
    );
  }

  function logout() {
    localStorage.removeItem('balansoft_panel_token');
    localStorage.removeItem('balansoft_panel_user');
    window.location.replace('index.html');
  }

  function requireSession() {
    if (!localStorage.getItem('balansoft_panel_token')) {
      window.location.replace('index.html');
    }
  }

  function sessionUser() {
    try {
      return JSON.parse(localStorage.getItem('balansoft_panel_user') || 'null');
    } catch (_) {
      return null;
    }
  }

  window.BalansoftAuth = {
    login: login,
    saveSession: saveSession,
    logout: logout,
    requireSession: requireSession,
    sessionUser: sessionUser,
  };
})();