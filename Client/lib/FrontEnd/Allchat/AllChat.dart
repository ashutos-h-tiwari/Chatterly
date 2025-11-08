import 'package:flutter/material.dart';

class AllChatsPage extends StatelessWidget {
  // Dummy user data and chats
  final List<Map<String, dynamic>> stories = [
    {'name': 'My Story', 'image': 'assets/story1.png'},
    {'name': 'Eleanor P', 'image': 'assets/story2.png'},
    {'name': 'Dianne R', 'image': 'assets/story3.png'},
    {'name': 'Duy H', 'image': 'assets/story4.png'},
  ];

  final List<Map<String, dynamic>> chats = [
    {
      'avatar': 'assets/chitzyteam.png',
      'name': 'Chitzy Team',
      'lastMsg': 'Floyd: Good luck team! 🔥',
      'time': '09:38',
      'icon': Icons.bookmark,
      'unread': 1,
    },
    {
      'avatar': 'assets/jerome.png',
      'name': 'Jerome Bell',
      'lastMsg': 'Thanks aid',
      'time': '16:32',
      'icon': Icons.bookmark_border,
      'unread': 0,
    },
    {
      'avatar': 'assets/floyd.png',
      'name': 'Floyd Miles',
      'lastMsg': 'Hello, bro! Can you help me?',
      'time': '15:05',
      'icon': Icons.bookmark,
      'unread': 1,
    },
    {
      'avatar': 'assets/devon.png',
      'name': 'Devon Line',
      'lastMsg': '00:34',
      'time': '11:60',
      'icon': Icons.bookmark_border,
      'unread': 0,
    },
    {
      'avatar': 'assets/annette.png',
      'name': 'Annette Black',
      'lastMsg': 'Well, good job! 🔱',
      'time': 'Yesterday',
      'icon': Icons.bookmark_border,
      'unread': 0,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xffe6f3ee),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sutra', style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff197d6e),
                  )),
                  Icon(Icons.menu, size: 32, color: Color(0xff197d6e)),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0xff69b29d).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  decoration: InputDecoration(
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search, color: Color(0xff36a38d)),
                      hintText: "Search chat or contact",
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      contentPadding: EdgeInsets.symmetric(vertical: 16)
                  ),
                ),
              ),
            ),

            // Stories Scroll
            Container(
              height: 88,
              margin: const EdgeInsets.symmetric(vertical: 16),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 14),
                itemCount: stories.length,
                itemBuilder: (context, i) => Column(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xffc1f2e2),
                      backgroundImage: AssetImage(stories[i]['image']),
                      child: stories[i]['name'] == 'My Story'
                          ? Align(
                        alignment: Alignment.bottomRight,
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.add, size: 16, color: Color(0xff36a38d)),
                        ),
                      )
                          : null,
                    ),
                    SizedBox(height: 6),
                    SizedBox(
                      width: 70,
                      child: Text(
                        stories[i]['name'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Color(0xff36a38d)),
                      ),
                    ),
                  ],
                ),
                separatorBuilder: (context, i) => SizedBox(width: 12),
              ),
            ),

            // Chats header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("All Chats",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Color(0xff197d6e),
                      )),
                  Icon(Icons.filter_alt_outlined, color: Color(0xff197d6e))
                ],
              ),
            ),

            // Chat List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(18),
                itemBuilder: (context, i) => Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: Color(0xffc1f2e2),
                        backgroundImage: AssetImage(chats[i]['avatar']),
                      ),
                      title: Text(chats[i]['name'],
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xff197d6e))),
                      subtitle: Text(chats[i]['lastMsg'],
                          style: TextStyle(color: Colors.black54)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(chats[i]['time'], style: TextStyle(
                              fontSize: 13, color: Color(0xffafbeb7))),
                          if(chats[i]['unread'] > 0)
                            Container(
                              margin: EdgeInsets.only(top: 2),
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Color(0xff36a38d),
                                  borderRadius: BorderRadius.circular(12)
                              ),
                              child: Text('${chats[i]['unread']}', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ),
                        ],
                      )
                  ),
                ),
                separatorBuilder: (context, i) => SizedBox(height: 10),
                itemCount: chats.length,
              ),
            )
          ],
        ),
      ),

      // Bottom nav bar
      bottomNavigationBar: Container(
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: Color(0xffffffff),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble, color: Color(0xff36a38d)),
                Text("Chats", style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xff36a38d))),
              ],
            ),
            Container(
              height: 48, width: 48,
              child: FloatingActionButton(
                onPressed: () {},
                child: Icon(Icons.add, color: Colors.white, size: 28),
                backgroundColor: Color(0xff36a38d),
                elevation: 1,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call, color: Color(0xff197d6e)),
                Text("Calls", style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xff197d6e))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
