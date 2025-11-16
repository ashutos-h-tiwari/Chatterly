// lib/story_page.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// MODELS
class StoryItem {
  final String imageUrl;
  final String caption;
  StoryItem({required this.imageUrl, this.caption = ''});
}

class PersonStories {
  final String id;
  final String name;
  final String avatarUrl;
  final List<StoryItem> stories;
  PersonStories({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.stories,
  });
}

/// MAIN STORY PAGE — Only rectangular tiles, random size
class StoryPage extends StatelessWidget {
  final List<PersonStories>? people;
  const StoryPage({super.key, this.people});

  static const List<Color> _bgGradient = [
    Color(0xFF120A2A),
    Color(0xFF311B6B),
    Color(0xFFBFA2FF),
  ];

  @override
  Widget build(BuildContext context) {
    final list = people ?? _samplePeople;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: _bgGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// HEADER
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "Stories",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onPressed: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Text(
                    "All Stories",
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),

                  /// MASONRY GRID — rectangular tiles
                  MasonryGridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final p = list[i];
                      final hero =
                      p.stories.isNotEmpty ? p.stories.first.imageUrl : "";

                      /// random height for Pinterest effect
                      final randomHeight =
                          150 + Random(i * 77).nextInt(200); // 150–350 px

                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => StoryViewer(person: p)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// STORY IMAGE BOX (rectangle)
                            Container(
                              height: randomHeight.toDouble(),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                image: DecorationImage(
                                  fit: BoxFit.cover,
                                  image: NetworkImage(hero),
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),

                            /// NAME TEXT
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// STORY VIEWER (unchanged)
class StoryViewer extends StatefulWidget {
  final PersonStories person;
  final int initialIndex;
  const StoryViewer({super.key, required this.person, this.initialIndex = 0});

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late PageController _pc;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pc = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stories = widget.person.stories;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pc,
              itemCount: stories.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final s = stories[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      child: s.imageUrl.isNotEmpty
                          ? Image.network(s.imageUrl, fit: BoxFit.cover)
                          : Container(color: Colors.grey[900]),
                    ),
                    if (s.caption.isNotEmpty)
                      Positioned(
                        bottom: 40,
                        left: 20,
                        right: 20,
                        child: Text(
                          s.caption,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                        ),
                      ),
                  ],
                );
              },
            ),

            /// TOP BAR
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  CircleAvatar(
                    radius: 17,
                    backgroundImage: NetworkImage(widget.person.avatarUrl),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.person.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ),
                  Text(
                    "${_index + 1}/${stories.length}",
                    style:
                    const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SAMPLE DATA
final List<PersonStories> _samplePeople = List.generate(18, (index) {
  return PersonStories(
    id: 'p$index',
    name: [
      'Ava',
      'Mia',
      'Liam',
      'Noah',
      'Ella',
      'Aria',
      'Ethan',
      'Leo',
      'Zara',
      'Elena',
      'Finn',
      'Mila'
    ][index % 12],
    avatarUrl: "https://i.pravatar.cc/150?img=${(index % 70) + 1}",
    stories: List.generate(
      2 + (index % 3),
          (i) => StoryItem(
        imageUrl: "https://picsum.photos/seed/${index}_$i/600/900",
        caption: "Story ${i + 1}",
      ),
    ),
  );
});
