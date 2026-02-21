const Map<String, dynamic> defaultIceServers = {
  'iceServers': [
    {
      'urls': ['stun:stun.l.google.com:19302'], // STUN - no credentials needed
    },
    {
      'urls': ['turn:openrelay.metered.ca:80'],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': ['turn:openrelay.metered.ca:443'],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ]
};
