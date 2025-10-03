// lib/notes_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/gig_model.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:url_launcher/url_launcher.dart';

class NotesPage extends StatefulWidget {
  // Now only needs the ID. It will fetch the rest.
  final String editingGigId;

  const NotesPage({
    super.key,
    required this.editingGigId,
  });

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  // Controllers are initialized later
  late final TextEditingController _notesController;
  late final TextEditingController _urlController;

  // State for holding the fetched data
  Gig? _gig;
  bool _isLoading = true;
  String _errorMessage = '';

  // State for UI and saving logic
  bool _isEditingUrl = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    // Initialize controllers empty, they will be populated after loading.
    _notesController = TextEditingController();
    _urlController = TextEditingController();
    _loadGigDetails();
  }

  /// NEW: Fetches the specific gig's details from SharedPreferences on start.
  Future<void> _loadGigDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
      final List<Gig> allGigs = Gig.decode(gigsJsonString);
      final gigIndex = allGigs.indexWhere((g) => g.id == widget.editingGigId);

      if (gigIndex != -1) {
        if (mounted) {
          setState(() {
            _gig = allGigs[gigIndex];
            _notesController.text = _gig!.notes ?? '';
            _urlController.text = _gig!.notesUrl ?? '';
            _isEditingUrl = _gig!.notesUrl == null || _gig!.notesUrl!.isEmpty;
            _isLoading = false;

            // Add listeners after controllers are populated
            _notesController.addListener(_onTextChanged);
            _urlController.addListener(_onTextChanged);
          });
        }
      } else {
        throw Exception("Gig not found.");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error loading gig details: $e";
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _notesController.removeListener(_onTextChanged);
    _urlController.removeListener(_onTextChanged);
    _notesController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_gig == null) return;
    final bool notesChanged = _notesController.text != (_gig!.notes ?? '');
    final bool urlChanged = _urlController.text != (_gig!.notesUrl ?? '');

    if (mounted && (notesChanged || urlChanged) != _hasChanges) {
      setState(() {
        _hasChanges = notesChanged || urlChanged;
      });
    }
  }

  Future<void> _launchUrl() async {
    // This method remains unchanged
    final urlString = _urlController.text.trim();
    if (urlString.isEmpty) return;
    final Uri? uri = Uri.tryParse(
        urlString.startsWith('http') ? urlString : 'https://$urlString');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $urlString'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveNotesAndClose() async {
    // This method remains unchanged and is already robust
    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String gigsJsonString = prefs.getString('gigs_list') ?? '[]';
      List<Gig> currentGigs = Gig.decode(gigsJsonString);
      final gigIndex = currentGigs.indexWhere((g) => g.id == widget.editingGigId);
      if (gigIndex != -1) {
        final newNotes = _notesController.text.trim();
        final newUrl = _urlController.text.trim();
        currentGigs[gigIndex] = currentGigs[gigIndex].copyWith(
          notes: newNotes.isEmpty ? null : newNotes,
          notesUrl: newUrl.isEmpty ? null : newUrl,
        );
        await prefs.setString('gigs_list', Gig.encode(currentGigs));
        globalRefreshNotifier.notify();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notes saved successfully!'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pop();
        }
      } else {
        throw Exception("Could not find the gig to update. It may have been deleted.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving notes: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NOTES'),
        centerTitle: true,
        automaticallyImplyLeading: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_errorMessage, style: const TextStyle(color: Colors.red))))
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 120.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _gig!.venueName, // Use data from the fetched _gig object
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              DateFormat.yMMMEd().add_jm().format(_gig!.dateTime), // Use data from _gig
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _notesController,
              autofocus: true,
              maxLines: 8,
              minLines: 5,
              decoration: const InputDecoration(
                labelText: 'Gig-Specific Notes',
                hintText: 'Load-in details, sound engineer name, etc.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Related Link', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            if (_isEditingUrl)
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL (Optional)',
                  hintText: 'e.g., docs.google.com/setlist',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _launchUrl,
                      child: Text(
                        _urlController.text,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () {
                      setState(() {
                        _isEditingUrl = true;
                        _onTextChanged();
                      });
                    },
                    tooltip: 'Edit Link',
                  )
                ],
              ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12.0),
        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.95),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('CLOSE'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (_hasChanges && !_isSaving && !_isLoading) ? _saveNotesAndClose : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).copyWith(
                  backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                        (Set<MaterialState> states) {
                      if (states.contains(MaterialState.disabled)) {
                        return Colors.grey.shade700;
                      }
                      return Theme.of(context).colorScheme.primary;
                    },
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_hasChanges ? 'Save Changes' : 'Notes Saved'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
