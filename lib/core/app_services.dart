import '../services/ai_service.dart';
import '../services/assistant_controller.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/memory_service.dart';
import '../services/native_bridge.dart';
import '../services/stt_service.dart';
import '../services/tools_service.dart';
import '../services/tts_service.dart';
import 'secure_store.dart';
import 'settings.dart';

/// Tiny service locator. Created once in main().
class AppServices {
  AppServices._({
    required this.settings,
    required this.secure,
    required this.auth,
    required this.native,
    required this.memory,
    required this.backup,
    required this.tts,
    required this.ai,
    required this.stt,
    required this.assistant,
  });

  final AppSettings settings;
  final SecureStore secure;
  final AuthService auth;
  final NativeBridge native;
  final MemoryService memory;
  final BackupService backup;
  final TtsService tts;
  final AiService ai;
  final SttService stt;
  final AssistantController assistant;

  static AppServices? _i;
  static AppServices get I => _i!;

  static Future<AppServices> create() async {
    final settings = await AppSettings.load();
    final secure = SecureStore();
    final auth = AuthService(secure);
    final native = NativeBridge();
    final memory = MemoryService(auth);
    final backup = BackupService(auth, settings);
    final tts = TtsService(native, settings);
    final tools = ToolsService(native, settings, auth);
    final ai = AiService(tools, auth);
    final stt = SttService();
    final assistant = AssistantController(
      settings: settings,
      native: native,
      tts: tts,
      stt: stt,
      ai: ai,
      memory: memory,
      tools: tools,
      auth: auth,
    );
    _i = AppServices._(
      settings: settings,
      secure: secure,
      auth: auth,
      native: native,
      memory: memory,
      backup: backup,
      tts: tts,
      ai: ai,
      stt: stt,
      assistant: assistant,
    );
    return _i!;
  }
}

AppServices get S => AppServices.I;
