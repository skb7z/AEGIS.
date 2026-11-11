class K {
  K._();
  static const appName = 'Aegis';
  static const supportEmail = 'aegis.ai.support.team@gmail.com';

  // Free, key-less AI (OpenAI-compatible). If a model/endpoint stops working, change it here.
  static const aiEndpoints = [
    'https://gen.pollinations.ai/v1/chat/completions',
    'https://text.pollinations.ai/openai',
  ];
  static const aiModels = ['openai-fast', 'openai', 'mistral'];
  static const aiVisionModels = ['openai', 'gemini-fast'];

  static const channel = 'aegis/system';
  static const driveFile = 'aegis_memory.jsonl';
  static const driveScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const offlineLine = 'Sir, internet connection is lost. Please enable mobile data.';
  static const logoAsset = 'assets/images/aegis_logo.png';

  // Secure storage keys
  static const kName = 'profile_name';
  static const kEmail = 'profile_email';
  static const kPhoto = 'profile_photo';
  static const kGuest = 'guest_mode';
  static const kProfile = 'profile_json';
}
