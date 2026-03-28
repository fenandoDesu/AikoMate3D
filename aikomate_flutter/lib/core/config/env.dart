class Env {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const chatWsUrl = String.fromEnvironment(
    'CHAT_WS_URL',
    defaultValue: 'wss://api.japaneseblossom.com/ws/chat',
  );
}
