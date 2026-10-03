import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const QuranApp());

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'القرآن الكريم',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AudioPlayer _player = AudioPlayer();

  static const String _prefLastSurah = 'last_surah';
  static const String _prefLastReciter = 'last_reciter_id';

  static const List<String> _surahNames = [
    'الفاتحة', 'البقرة', 'آل عمران', 'النساء', 'المائدة', 'الأنعام',
    'الأعراف', 'الأنفال', 'التوبة', 'يونس', 'هود', 'يوسف', 'الرعد',
    'إبراهيم', 'الحجر', 'النحل', 'الإسراء', 'الكهف', 'مريم', 'طه',
    'الأنبياء', 'الحج', 'المؤمنون', 'النور', 'الفرقان', 'الشعراء',
    'النمل', 'القصص', 'العنكبوت', 'الروم', 'لقمان', 'السجدة',
    'الأحزاب', 'سبأ', 'فاطر', 'يس', 'الصافات', 'ص', 'الزمر', 'غافر',
    'فصلت', 'الشورى', 'الزخرف', 'الدخان', 'الجاثية', 'الأحقاف',
    'محمد', 'الفتح', 'الحجرات', 'ق', 'الذاريات', 'الطور', 'النجم',
    'القمر', 'الرحمن', 'الواقعة', 'الحديد', 'المجادلة', 'الحشر',
    'الممتحنة', 'الصف', 'الجمعة', 'المنافقون', 'التغابن', 'الطلاق',
    'التحريم', 'الملك', 'القلم', 'الحاقة', 'المعارج', 'نوح', 'الجن',
    'المزمل', 'المدثر', 'القيامة', 'الإنسان', 'المرسلات', 'النبأ',
    'النازعات', 'عبس', 'التكوير', 'الإنفطار', 'المطففين', 'الإنشقاق',
    'البروج', 'الطارق', 'الأعلى', 'الغاشية', 'الفجر', 'البلد',
    'الشمس', 'الليل', 'الضحى', 'الشرح', 'التين', 'العلق', 'القدر',
    'البينة', 'الزلزلة', 'العاديات', 'القارعة', 'التكاثر', 'العصر',
    'الهمزة', 'الفيل', 'قريش', 'الماعون', 'الكوثر', 'الكافرون',
    'النصر', 'المسد', 'الإخلاص', 'الفلق', 'الناس',
  ];

  // الحالة
  List<dynamic> _reciters = [];
  dynamic _selectedReciter;
  int? _currentSurah;
  String _serverUrl = '';
  bool _loadingText = false;
  bool _loadingAudio = false;
  bool _isRepeat = false;
  bool _autoNext = true;
  bool _audioLoaded = false;
  String _status = 'مرحباً بك في القرآن الكريم';

  @override
  void initState() {
    super.initState();
    _setupPlayerListeners();
    _loadReciters();
    _restoreState();
  }

  // ======================== استرجاع الحالة المحفوظة ========================
  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSurah = prefs.getInt(_prefLastSurah) ?? 1; // الافتراضي: الفاتحة
    // تحميل النص فقط، دون تشغيل الصوت
    _loadSurahTextOnly(savedSurah, savePreference: false);
  }

  Future<void> _saveLastSurah(int n) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefLastSurah, n);
  }

  // ======================== المستمعون ========================
  void _setupPlayerListeners() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_isRepeat && _currentSurah != null) {
          _playSurahAudio(_currentSurah!);
        } else if (_autoNext &&
            _currentSurah != null &&
            _currentSurah! < 114) {
          _selectSurah(_currentSurah! + 1);
        }
      }
      if (mounted) setState(() {});
    });
  }

  // ======================== تحميل القراء ========================
  Future<void> _loadReciters() async {
    try {
      final res = await http.get(
        Uri.parse('https://mp3quran.net/api/v3/reciters?language=ar'),
      );
      if (res.statusCode != 200) return;
      final data = json.decode(res.body);
      setState(() => _reciters = data['reciters'] ?? []);

      // استرجاع القارئ المحفوظ
      final prefs = await SharedPreferences.getInstance();
      final savedReciterId = prefs.getInt(_prefLastReciter);
      if (savedReciterId != null) {
        for (final r in _reciters) {
          if (r['id'] == savedReciterId) {
            setState(() {
              _selectedReciter = r;
              _serverUrl = _extractServerUrl(r);
            });
            break;
          }
        }
      }
    } catch (e) {
      setState(() => _status = 'فشل تحميل القراء: $e');
    }
  }

  Future<void> _saveLastReciter(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefLastReciter, id);
  }

  // ======================== تحميل النص فقط ========================
  Future<void> _loadSurahTextOnly(
    int surahNumber, {
    bool savePreference = true,
  }) async {
    setState(() {
      _currentSurah = surahNumber;
      _ayahs = [];
      _loadingText = true;
      _status = 'جاري تحميل النص...';
    });

    if (savePreference) {
      await _saveLastSurah(surahNumber);
    }

    try {
      final res = await http.get(
        Uri.parse('https://api.quranpedia.net/v1/mushafs/1/$surahNumber'),
      );

      if (res.statusCode != 200) {
        setState(() {
          _loadingText = false;
          _status = 'خطأ في النص: HTTP ${res.statusCode}';
        });
        return;
      }

      final data = json.decode(res.body);
      final List<dynamic> ayahs = data is List ? data : (data['ayahs'] ?? []);

      setState(() {
        _ayahs = ayahs;
        _loadingText = false;
        _status = 'سورة ${_surahNames[surahNumber - 1]}';
      });
    } catch (e) {
      setState(() {
        _loadingText = false;
        _status = 'فشل تحميل النص: $e';
      });
    }
  }

  // ======================== اختيار سورة (نص + صوت) ========================
  Future<void> _selectSurah(int surahNumber) async {
    if (_selectedReciter == null) {
      setState(() => _status = 'الرجاء اختيار قارئ أولاً');
      return;
    }

    // 1. تحميل النص
    await _loadSurahTextOnly(surahNumber);

    // 2. تشغيل الصوت
    _serverUrl = _extractServerUrl(_selectedReciter);
    await _playSurahAudio(surahNumber);
  }

  // ======================== تشغيل الصوت ========================
  Future<void> _playSurahAudio(int surahNumber) async {
    if (_serverUrl.isEmpty) {
      setState(() {
        _loadingAudio = false;
        _status = 'لا يوجد رابط صوت لهذا القارئ';
      });
      return;
    }

    final number = surahNumber.toString().padLeft(3, '0');
    final url = '$_serverUrl$number.mp3';

    try {
      setState(() {
        _loadingAudio = true;
        _status = 'جاري التشغيل...';
      });
      await _player.setUrl(url);
      _player.play();
      setState(() {
        _loadingAudio = false;
        _audioLoaded = true;
        _status = '▶ يعمل الآن: سورة ${_surahNames[surahNumber - 1]}';
      });
    } catch (e) {
      setState(() {
        _loadingAudio = false;
        _audioLoaded = false;
        _status = 'فشل الصوت: $e';
      });
    }
  }

  // ======================== استخراج رابط الخادم ========================
  String _extractServerUrl(dynamic reciter) {
    try {
      final moshaf = reciter['moshaf'];
      if (moshaf is List && moshaf.isNotEmpty) {
        for (final m in moshaf) {
          final s = m['server'];
          if (s != null && s.toString().isNotEmpty) {
            return s.toString();
          }
        }
      } else if (moshaf is Map) {
        return (moshaf['server'] ?? '').toString();
      }
    } catch (_) {}
    return '';
  }

  // ======================== أدوات التحكم ========================
  void _togglePlay() {
    if (_currentSurah == null) return;

    if (_serverUrl.isEmpty && _selectedReciter != null) {
      _serverUrl = _extractServerUrl(_selectedReciter);
    }

    if (_player.playing) {
      _player.pause();
    } else {
      if (!_audioLoaded) {
        _playSurahAudio(_currentSurah!);
      } else {
        _player.play();
      }
    }
    setState(() {});
  }

  void _playNext() {
    if (_currentSurah != null && _currentSurah! < 114) {
      _selectSurah(_currentSurah! + 1);
    }
  }

  void _playPrevious() {
    if (_currentSurah != null && _currentSurah! > 1) {
      _selectSurah(_currentSurah! - 1);
    }
  }

  void _restart() {
    if (_currentSurah != null && _audioLoaded) {
      _player.seek(Duration.zero);
      _player.play();
      setState(() {});
    }
  }

  void _toggleRepeat() {
    setState(() {
      _isRepeat = !_isRepeat;
      if (_isRepeat) _autoNext = false;
    });
  }

  void _toggleAutoNext() {
    setState(() {
      _autoNext = !_autoNext;
      if (_autoNext) _isRepeat = false;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // ======================== الواجهة ========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('القرآن الكريم'),
        centerTitle: true,
        actions: [
          if (_reciters.isNotEmpty)
            PopupMenuButton<dynamic>(
              icon: const Icon(Icons.person),
              tooltip: 'اختر قارئاً',
              onSelected: (r) {
                setState(() {
                  _selectedReciter = r;
                  _serverUrl = _extractServerUrl(r);
                  _audioLoaded = false;
                  _status = 'تم اختيار القارئ: ${r['name']}';
                });
                if (r['id'] != null) _saveLastReciter(r['id']);
              },
              itemBuilder: (_) => _reciters
                  .map<PopupMenuEntry<dynamic>>(
                    (r) => PopupMenuItem(value: r, child: Text(r['name'] ?? '')),
                  )
                  .toList(),
            ),
        ],
      ),
      body: Column(
        children: [
          // شريط الحالة
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            color: Colors.green.shade50,
            child: Text(
              _status,
              style: TextStyle(fontSize: 12, color: Colors.green.shade900),
              textAlign: TextAlign.center,
            ),
          ),

          // منطقة النص
          Expanded(
            child: _loadingText
                ? const Center(child: CircularProgressIndicator())
                : _ayahs.isEmpty
                ? const Center(child: Text('اختر سورة من الزر العائم 📖'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _ayahs.length,
                    itemBuilder: (context, i) {
                      final a = _ayahs[i];
                      final text = a['text']?.toString() ?? '';
                      final number = a['number']?.toString() ?? '${i + 1}';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              text,
                              style: const TextStyle(
                                fontSize: 22,
                                height: 1.9,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '﴿ $number ﴾',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // مشغل الصوت
          _buildPlayer(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSurahPicker,
        child: const Icon(Icons.menu_book),
      ),
    );
  }

  // ======================== بناء المشغل ========================
  Widget _buildPlayer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // معلومات السورة والقارئ + أزرار الإعدادات
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child: const Icon(Icons.menu_book, color: Colors.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentSurah != null
                              ? 'سورة ${_surahNames[_currentSurah! - 1]}'
                              : 'لم تُختَر سورة',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          _selectedReciter?['name'] ?? 'لم يُختَر قارئ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // زر إعادة التشغيل
                  IconButton(
                    icon: const Icon(Icons.replay),
                    color: Colors.grey[700],
                    onPressed: _currentSurah != null && _audioLoaded
                        ? _restart
                        : null,
                    tooltip: 'إعادة من البداية',
                  ),
                  // زر التكرار
                  IconButton(
                    icon: Icon(
                      _isRepeat ? Icons.repeat_one : Icons.repeat,
                      color: _isRepeat ? Colors.green : Colors.grey,
                    ),
                    onPressed: _toggleRepeat,
                    tooltip: _isRepeat ? 'تكرار السورة' : 'تكرار معطل',
                  ),
                  // زر التنقل التلقائي
                  IconButton(
                    icon: Icon(
                      _autoNext ? Icons.playlist_play : Icons.playlist_remove,
                      color: _autoNext ? Colors.green : Colors.grey,
                    ),
                    onPressed: _toggleAutoNext,
                    tooltip: _autoNext
                        ? 'التنقل التلقائي مفعّل'
                        : 'التنقل التلقائي معطل',
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // شريط التقدم
              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final total = _player.duration ?? Duration.zero;
                  final max = total.inMilliseconds.toDouble();
                  final value = position.inMilliseconds
                      .clamp(0, max > 0 ? max : 1)
                      .toDouble();

                  return Column(
                    children: [
                      Slider(
                        min: 0,
                        max: max > 0 ? max : 1,
                        value: value,
                        onChanged: _audioLoaded
                            ? (v) {
                                _player.seek(
                                  Duration(milliseconds: v.toInt()),
                                );
                              }
                            : null,
                        activeColor: Colors.green,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(fontSize: 11),
                            ),
                            Text(
                              _formatDuration(total),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              // أزرار التحكم
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: _currentSurah != null && _currentSurah! > 1
                        ? _playPrevious
                        : null,
                  ),
                  _loadingAudio
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                        )
                      : IconButton(
                          iconSize: 56,
                          color: Colors.green,
                          icon: Icon(
                            _player.playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                          ),
                          onPressed: _currentSurah != null ? _togglePlay : null,
                        ),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_next),
                    onPressed: _currentSurah != null && _currentSurah! < 114
                        ? _playNext
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ======================== منتقي السور ========================
  void _showSurahPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.menu_book, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text(
                    'اختر سورة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: 114,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = i + 1;
                  final isCurrent = _currentSurah == n;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCurrent
                          ? Colors.green
                          : Colors.green.shade100,
                      child: Text(
                        '$n',
                        style: TextStyle(
                          fontSize: 12,
                          color: isCurrent
                              ? Colors.white
                              : Colors.green.shade900,
                        ),
                      ),
                    ),
                    title: Text(
                      'سورة ${_surahNames[i]}',
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent ? Colors.green : null,
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.play_arrow, color: Colors.green)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      _selectSurah(n);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================== تنسيق المدة ========================
  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }
}