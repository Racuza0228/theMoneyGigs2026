// lib/features/setlists/services/music_facts_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MusicFactsService {
  static const String _mbBaseUrl = 'https://musicbrainz.org/ws/2';
  static const String _wikiBaseUrl = 'https://en.wikipedia.org/w/api.php';
  static const String _userAgent = 'MoneyGigs/1.1.4 (cliff@themoneygigs.com)';

  // Rate limiting: max 1 request per second
  static DateTime? _lastRequestTime;
  static const Duration _minRequestInterval = Duration(seconds: 1, milliseconds: 100);

  // Cache to avoid redundant API calls
  static final Map<String, Map<String, dynamic>> _cache = {};

  /// Main entry point - gets comprehensive song facts
  /// Returns a map with all the interesting facts about the song/artist
  static Future<Map<String, dynamic>?> fetchSongFacts(
      String songTitle,
      String? artistName, {
        String? venueCity,
      }) async {
    if (artistName == null || artistName.isEmpty) return null;

    final cacheKey = '${artistName}_$songTitle';
    if (_cache.containsKey(cacheKey)) {
      return _enrichWithLocationContext(_cache[cacheKey]!, venueCity);
    }

    try {
      // Step 1: Search for the recording
      final recordingData = await _searchRecording(songTitle, artistName);
      if (recordingData == null) return null;

      final artistId = recordingData['artistId'] as String;
      final artistNameResult = recordingData['artistName'] as String;
      final releaseYear = recordingData['releaseYear'] as String?;
      final songDetails = recordingData['songDetails'] as Map<String, dynamic>?;

      // Step 2: Get artist details including band members
      final artistDetails = await _getArtistDetails(artistId);

      // Step 3: Try to get Wikipedia summary
      String? wikiSummary;
      final wikipediaTitle = artistDetails['wikipediaTitle'] as String?;
      if (wikipediaTitle != null) {
        wikiSummary = await _getWikipediaSummary(wikipediaTitle);
      }

      // Combine all the data
      final facts = {
        'artistName': artistNameResult,
        'hometown': artistDetails['hometown'],
        'country': artistDetails['country'],
        'bandMembers': artistDetails['bandMembers'] ?? [],
        'collaborators': artistDetails['collaborators'] ?? [],
        'wikiSummary': wikiSummary,
        'releaseYear': releaseYear,
        'songDetails': songDetails,
      };

      _cache[cacheKey] = facts;
      return _enrichWithLocationContext(facts, venueCity);

    } catch (e) {
      print('Error fetching music facts: $e');
      return null;
    }
  }

  /// Search for recording and return basic info with relationships
  static Future<Map<String, dynamic>?> _searchRecording(
      String title,
      String artist,
      ) async {
    // First search for the recording
    final searchQuery = 'recording:"$title" AND artist:"$artist"';
    final searchUrl = Uri.parse(
        '$_mbBaseUrl/recording/?query=$searchQuery&fmt=json&limit=1'
    );

    final searchResponse = await _makeRequest(searchUrl);
    if (searchResponse == null || searchResponse.statusCode != 200) return null;

    final searchData = json.decode(searchResponse.body);
    final recordings = searchData['recordings'] as List?;

    if (recordings == null || recordings.isEmpty) return null;

    final recording = recordings[0];
    final recordingId = recording['id'] as String;

    // Now get full recording details with work relationships
    final detailsUrl = Uri.parse(
        '$_mbBaseUrl/recording/$recordingId?'
            'inc=artist-credits+releases+work-rels+work-level-rels+artist-rels&fmt=json'
    );

    final detailsResponse = await _makeRequest(detailsUrl);
    if (detailsResponse == null || detailsResponse.statusCode != 200) return null;

    final details = json.decode(detailsResponse.body);

    // Extract artist info
    final artistCredit = details['artist-credit'] as List?;
    final artistId = artistCredit?[0]['artist']['id'] as String?;
    final artistName = artistCredit?[0]['name'] as String?;

    // Extract song-specific details from work relationships
    final Map<String, dynamic> songDetails = {};
    final relations = details['relations'] as List? ?? [];

    // Find composers and lyricists from work relationships
    final List<String> composers = [];
    final List<String> lyricists = [];
    final List<String> producers = [];

    for (var rel in relations) {
      final relType = rel['type'] as String?;

      // Get work relationships
      if (rel['work'] != null) {
        final work = rel['work'];
        final workRelations = work['relations'] as List? ?? [];

        for (var workRel in workRelations) {
          final workRelType = workRel['type'] as String?;
          final artist = workRel['artist'];

          if (artist != null) {
            final artistName = artist['name'] as String;

            if (workRelType == 'composer' && !composers.contains(artistName)) {
              composers.add(artistName);
            } else if (workRelType == 'lyricist' && !lyricists.contains(artistName)) {
              lyricists.add(artistName);
            }
          }
        }
      }

      // Get recording-level relationships (producers, etc)
      if (relType == 'producer') {
        final artist = rel['artist'];
        if (artist != null) {
          final producerName = artist['name'] as String;
          if (!producers.contains(producerName)) {
            producers.add(producerName);
          }
        }
      }
    }

    songDetails['composers'] = composers;
    songDetails['lyricists'] = lyricists;
    songDetails['producers'] = producers;

    // Extract release year
    String? releaseYear;
    final releases = details['releases'] as List?;
    if (releases != null && releases.isNotEmpty) {
      final firstRelease = releases[0];
      final date = firstRelease['date'] as String?;
      if (date != null && date.length >= 4) {
        releaseYear = date.substring(0, 4);
      }
    }

    return {
      'artistId': artistId,
      'artistName': artistName,
      'releaseYear': releaseYear,
      'songDetails': songDetails,
    };
  }

  /// Get comprehensive artist details including band members
  static Future<Map<String, dynamic>> _getArtistDetails(String artistId) async {
    final url = Uri.parse(
        '$_mbBaseUrl/artist/$artistId?'
            'inc=url-rels+artist-rels+aliases&fmt=json'
    );

    final response = await _makeRequest(url);
    if (response == null || response.statusCode != 200) {
      return {
        'bandMembers': [],
        'collaborators': [],
      };
    }

    final data = json.decode(response.body);

    // Extract location info
    final beginArea = data['begin-area'];
    final hometown = beginArea?['name'] as String?;
    final area = data['area'];
    final country = area?['name'] as String?;

    // Extract Wikipedia link
    String? wikipediaTitle;
    final relations = data['relations'] as List? ?? [];
    for (var rel in relations) {
      if (rel['type'] == 'wikipedia' && rel['url'] != null) {
        final wikiUrl = rel['url']['resource'] as String?;
        if (wikiUrl != null) {
          try {
            wikipediaTitle = Uri.parse(wikiUrl).pathSegments.last;
          } catch (e) {
            print('Error parsing Wikipedia URL: $e');
          }
        }
        break;
      }
    }

    // Extract band members or collaborations
    final List<Map<String, dynamic>> bandMembers = [];
    final List<String> collaborators = [];

    for (var rel in relations) {
      final relType = rel['type'] as String?;
      final direction = rel['direction'] as String?;

      // This artist was a member of another band
      if (relType == 'member of band' && direction == 'forward') {
        final targetArtist = rel['artist'];
        if (targetArtist != null) {
          final bandName = targetArtist['name'] as String;
          if (!collaborators.contains(bandName)) {
            collaborators.add(bandName);
          }
        }
      }

      // Another artist was a member of THIS band (if this is a group)
      if (relType == 'member of band' && direction == 'backward') {
        final member = rel['artist'];
        if (member != null) {
          final attributes = rel['attributes'] as List? ?? [];
          final instruments = attributes
              .where((attr) => attr is String)
              .cast<String>()
              .toList();

          bandMembers.add({
            'name': member['name'],
            'id': member['id'],
            'instruments': instruments,
            'hometown': null, // Will be filled in next step
            'country': null,
          });
        }
      }
    }

    // Get band member details (limit to top 3 to avoid too many API calls)
    if (bandMembers.isNotEmpty) {
      final membersToEnrich = bandMembers.take(3).toList();
      for (var member in membersToEnrich) {
        final memberDetails = await _getArtistBasicInfo(member['id'] as String);
        member['hometown'] = memberDetails['hometown'];
        member['country'] = memberDetails['country'];
      }
    }

    return {
      'hometown': hometown,
      'country': country,
      'wikipediaTitle': wikipediaTitle,
      'bandMembers': bandMembers,
      'collaborators': collaborators,
    };
  }

  /// Get basic artist info (used for band members)
  static Future<Map<String, dynamic>> _getArtistBasicInfo(String artistId) async {
    final url = Uri.parse('$_mbBaseUrl/artist/$artistId?fmt=json');

    final response = await _makeRequest(url);
    if (response == null || response.statusCode != 200) return {};

    final data = json.decode(response.body);

    final beginArea = data['begin-area'];
    final hometown = beginArea?['name'] as String?;
    final area = data['area'];
    final country = area?['name'] as String?;

    return {
      'hometown': hometown,
      'country': country,
    };
  }

  /// Get Wikipedia summary for interesting facts
  static Future<String?> _getWikipediaSummary(String articleTitle) async {
    try {
      final url = Uri.parse(
          '$_wikiBaseUrl?'
              'action=query&'
              'format=json&'
              'prop=extracts&'
              'exintro=true&'
              'explaintext=true&'
              'redirects=true&'
              'titles=$articleTitle'
      );

      final response = await http.get(url);
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final pages = data['query']['pages'] as Map<String, dynamic>?;

      if (pages != null) {
        final page = pages.values.first;
        final extract = page['extract'] as String?;

        // Return first 3 sentences
        if (extract != null) {
          final sentences = extract.split('. ');
          if (sentences.length >= 3) {
            return sentences.take(3).join('. ') + '.';
          }
          return extract;
        }
      }
    } catch (e) {
      print('Error fetching Wikipedia summary: $e');
    }

    return null;
  }

  /// Enrich facts with location-specific context
  static Map<String, dynamic> _enrichWithLocationContext(
      Map<String, dynamic> facts,
      String? venueCity,
      ) {
    final List<String> locationFacts = [];

    final artistHometown = facts['hometown'] as String?;
    final bandMembers = facts['bandMembers'] as List? ?? [];

    // Check for hometown match with venue
    if (venueCity != null && artistHometown != null) {
      if (_citiesMatch(venueCity, artistHometown)) {
        locationFacts.add('This artist is from $artistHometown!');
      }
    }

    // Check band members for location connections
    for (var member in bandMembers) {
      final memberName = member['name'] as String;
      final memberHometown = member['hometown'] as String?;
      final instruments = member['instruments'] as List?;

      if (memberHometown != null && venueCity != null) {
        if (_citiesMatch(venueCity, memberHometown)) {
          final instrumentStr = instruments != null && instruments.isNotEmpty
              ? ' (${instruments.join(", ")})'
              : '';
          locationFacts.add('$memberName$instrumentStr is from $memberHometown!');
        }
      }
    }

    return {
      ...facts,
      'locationFacts': locationFacts,
    };
  }

  /// Simple city name matching (can be enhanced)
  static bool _citiesMatch(String city1, String city2) {
    final normalized1 = city1.toLowerCase().trim();
    final normalized2 = city2.toLowerCase().trim();

    return normalized1 == normalized2 ||
        normalized1.contains(normalized2) ||
        normalized2.contains(normalized1);
  }

  /// Rate-limited HTTP GET request
  static Future<http.Response?> _makeRequest(Uri url) async {
    // Enforce rate limit
    if (_lastRequestTime != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastRequestTime!);
      if (timeSinceLastRequest < _minRequestInterval) {
        await Future.delayed(_minRequestInterval - timeSinceLastRequest);
      }
    }

    _lastRequestTime = DateTime.now();

    try {
      return await http.get(
        url,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      );
    } catch (e) {
      print('HTTP request error: $e');
      return null;
    }
  }

  /// Clear cache (useful for testing or memory management)
  static void clearCache() {
    _cache.clear();
  }
}