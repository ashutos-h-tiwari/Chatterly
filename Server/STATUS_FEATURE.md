# WhatsApp-Like Status Feature - Complete Guide

## 🎯 Features Implemented

✅ **Upload Status** - Images, Videos, Audio to Cloudinary  
✅ **Auto 24-Hour Expiry** - MongoDB TTL index auto-deletes  
✅ **Real-Time Broadcasting** - Socket.io pushes new statuses instantly  
✅ **View Tracking** - See who viewed your status  
✅ **Live Updates** - All connected users see new statuses instantly  
✅ **Status Deletion** - Delete your own statuses  

---

## 📋 API Endpoints

### 1. **Upload Status**
```
POST /api/status/upload
```
**Headers:** 
- `Authorization: Bearer {token}`

**Body:** Form-data
- `media` - File (image, video, audio)
- `mediaType` - "image" | "video" | "audio"
- `caption` - (Optional) Caption text

**Response:**
```json
{
  "message": "Status uploaded successfully",
  "status": {
    "_id": "63a7f1d2e1c4d5f6g7h8i9j0",
    "userId": {
      "_id": "user_id",
      "name": "John Doe",
      "avatar": "url"
    },
    "mediaUrl": "https://res.cloudinary.com/...",
    "mediaType": "image",
    "caption": "Hello World",
    "viewers": [],
    "createdAt": "2024-02-22T10:30:00Z"
  }
}
```

**Example Postman:**
```
POST http://localhost:5000/api/status/upload
Headers:
  Authorization: Bearer your_jwt_token
Body (form-data):
  media: [select image/video/audio file]
  mediaType: image
  caption: My awesome status!
```

---

### 2. **Get All Statuses (Feed)**
```
GET /api/status
```
**Headers:**
- `Authorization: Bearer {token}`

**Response:** Array of user statuses (grouped by user, only 24-hour old)
```json
[
  {
    "user": {
      "_id": "user_id",
      "name": "Alice",
      "avatar": "url"
    },
    "statuses": [
      {
        "_id": "status_id_1",
        "mediaUrl": "https://res.cloudinary.com/...",
        "mediaType": "image",
        "caption": "Beautiful sunset",
        "viewers": [
          {
            "userId": {
              "_id": "viewer_id",
              "name": "Bob"
            },
            "viewedAt": "2024-02-22T10:45:00Z"
          }
        ],
        "createdAt": "2024-02-22T10:30:00Z"
      }
    ]
  }
]
```

---

### 3. **Get My Statuses**
```
GET /api/status/my-statuses
```
**Headers:**
- `Authorization: Bearer {token}`

**Response:** Your all statuses (not expired)
```json
[
  {
    "_id": "status_id",
    "mediaUrl": "https://res.cloudinary.com/...",
    "mediaType": "video",
    "caption": "My video",
    "viewers": [
      {
        "userId": { "_id": "user_id", "name": "Alice" },
        "viewedAt": "2024-02-22T11:00:00Z"
      }
    ],
    "createdAt": "2024-02-22T10:30:00Z"
  }
]
```

---

### 4. **Mark Status As Viewed**
```
POST /api/status/:statusId/view
```
**Headers:**
- `Authorization: Bearer {token}`

**Response:**
```json
{
  "message": "Status marked as viewed",
  "status": {
    "_id": "status_id",
    "viewers": [
      {
        "userId": { "_id": "your_id", "name": "You" },
        "viewedAt": "2024-02-22T11:00:00Z"
      }
    ]
  }
}
```

---

### 5. **Get Status Viewers**
```
GET /api/status/:statusId/viewers
```
**Headers:**
- `Authorization: Bearer {token}`

**Response:**
```json
{
  "statusId": "status_id",
  "viewersCount": 3,
  "viewers": [
    {
      "userId": {
        "_id": "user_id_1",
        "name": "Alice",
        "avatar": "url"
      },
      "viewedAt": "2024-02-22T11:00:00Z"
    },
    {
      "userId": {
        "_id": "user_id_2",
        "name": "Bob",
        "avatar": "url"
      },
      "viewedAt": "2024-02-22T11:05:00Z"
    }
  ]
}
```

---

### 6. **Delete Status**
```
DELETE /api/status/:statusId
```
**Headers:**
- `Authorization: Bearer {token}`

**Response:**
```json
{
  "message": "Status deleted successfully"
}
```

---

## 🔌 Socket.io Real-Time Events

### **Client Listens For:**

#### 1. **New Status Upload**
```javascript
socket.on('status:new', (payload) => {
  console.log('📸 New status:', payload);
  // Update UI to show new status in feed
  // payload: { statusId, userId, mediaUrl, mediaType, caption, user, uploadedAt }
});
```

#### 2. **Status View Notification**
```javascript
socket.on('status:view-notification', (payload) => {
  console.log('👁️ Someone viewed your status:', payload);
  // payload: { statusId, viewedBy, viewerName, viewedAt }
});
```

#### 3. **Status Deleted**
```javascript
socket.on('status:deleted', (payload) => {
  console.log('🗑️ Status deleted:', payload);
  // Remove from UI
  // payload: { statusId, userId, deletedAt }
});
```

#### 4. **Error Events**
```javascript
socket.on('status:error', (payload) => {
  console.error('❌ Error:', payload.message);
});
```

---

### **Client Sends:**

#### 1. **Broadcast Status Upload**
```javascript
// After REST API upload is successful
socket.emit('status:upload', {
  statusId: response.status._id,
  userId: currentUserId,
  mediaUrl: response.status.mediaUrl,
  mediaType: response.status.mediaType,
  caption: response.status.caption,
  user: {
    _id: currentUserData._id,
    name: currentUserData.name,
    avatar: currentUserData.avatar
  }
});
```

#### 2. **Notify Status View**
```javascript
// After marking as viewed via REST API
socket.emit('status:viewed', {
  statusId: statusId,
  userId: statusOwnerId,
  viewerName: currentUserName
});
```

#### 3. **Broadcast Status Deletion**
```javascript
// After DELETE API call successful
socket.emit('status:delete', {
  statusId: statusId,
  userId: currentUserId
});
```

---

## 📊 Status Model Structure

```javascript
{
  userId: ObjectId,           // Who uploaded (ref: User)
  mediaUrl: String,           // Cloudinary URL
  mediaType: String,          // "image" | "video" | "audio"
  caption: String,            // Optional caption
  viewers: [
    {
      userId: ObjectId,       // Who viewed (ref: User)
      viewedAt: Date          // When viewed
    }
  ],
  createdAt: Date,            // Auto-deleted after 24 hours (TTL)
  updatedAt: Date
}
```

---

## 🔄 24-Hour Auto-Expiry

**How it works:**
1. MongoDB TTL index monitors `createdAt` field
2. After 86400 seconds (24 hours), document auto-deletes
3. Runs every 60 seconds (default MongoDB interval)

```javascript
// In Status model
statusSchema.index({ createdAt: 1 }, { expireAfterSeconds: 86400 });
```

**If status created at: 2024-02-22 10:00 AM**  
**Auto-deletes at: 2024-02-23 10:00 AM**

---

## 🌍 Real-Time Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     User A (Uploader)                       │
└─────────────────────────────────────────────────────────────┘
              │
              ├─ 1. Upload file → {REST API POST /api/status/upload}
              │     ↓ (Cloudinary stores file, returns URL)
              │
              ├─ 2. Save to MongoDB with 24h TTL
              │              ↓
              ├─ 3. Emit socket event {status:upload}
              │              ↓
┌─────────────────────────────────────────────────────────────┐
│                  Socket.io Server (io)                      │
│    io.emit('status:new', {...}) → ALL CONNECTED USERS      │
└─────────────────────────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────┐
    │  All Other Users See New Status In Feed │
    │         (Real-time instant)             │
    └─────────────────────────────────────────┘
              │
              ├─ User B clicks status → socket.emit('status:viewed')
              │              ↓
              ├─ Server receives → updates viewers array
              │              ↓
              ├─ Sends {status:view-notification} to User A
              │              ↓
              User A sees "B viewed your status"
```

---

## 🔧 Frontend Implementation Example

### Upload Status
```javascript
async function uploadStatus(file, mediaType, caption) {
  const formData = new FormData();
  formData.append('media', file);
  formData.append('mediaType', mediaType);
  formData.append('caption', caption);

  const response = await fetch('/api/status/upload', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`
    },
    body: formData
  });

  const data = await response.json();

  // 📡 Broadcast via Socket.io
  socket.emit('status:upload', {
    statusId: data.status._id,
    userId: currentUser._id,
    mediaUrl: data.status.mediaUrl,
    mediaType: data.status.mediaType,
    caption: data.status.caption,
    user: currentUser
  });

  return data.status;
}
```

---

### View Status
```javascript
async function viewStatus(statusId, statusOwnerId) {
  const response = await fetch(`/api/status/${statusId}/view`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });

  // 📡 Notify socket event
  socket.emit('status:viewed', {
    statusId: statusId,
    userId: statusOwnerId,
    viewerName: currentUser.name
  });

  return await response.json();
}
```

---

### Delete Status
```javascript
async function deleteStatus(statusId) {
  const response = await fetch(`/api/status/${statusId}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });

  // 📡 Broadcast deletion
  socket.emit('status:delete', {
    statusId: statusId,
    userId: currentUser._id
  });

  return await response.json();
}
```

---

### Listen for Real-Time Updates
```javascript
// 1. New status in feed
socket.on('status:new', (status) => {
  console.log('New status from:', status.user.name);
  // Add to UI feed
  addStatusToFeed(status);
});

// 2. Someone viewed your status
socket.on('status:view-notification', (notification) => {
  console.log(`${notification.viewerName} viewed your status`);
  // Update viewer count in UI
  updateViewerCount(notification.statusId, notification);
});

// 3. Status deleted
socket.on('status:deleted', (data) => {
  console.log('Status deleted:', data.statusId);
  // Remove from UI
  removeStatusFromFeed(data.statusId);
});
```

---

## ✅ Checklist

- ✅ JWT authentication required for all endpoints
- ✅ Cloudinary storage for images/videos/audio
- ✅ MongoDB TTL auto-delete after 24 hours
- ✅ Real-time Socket.io broadcasting
- ✅ View tracking with timestamps
- ✅ Only status owner can delete
- ✅ Only status owner can see viewers
- ✅ Validation for media type

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| Status not showing in real-time | Ensure socket.io is connected & `status:upload` event sent |
| File upload fails | Check Cloudinary config & file size limits |
| Status not deleting after 24h | MongoDB TTL requires collection restart |
| Viewers not updating | Ensure `status:viewed` socket event is emitted after API call |

---

## 🚀 Testing with Postman

1. **Login & get token**
   ```
   POST /api/auth/login
   Body: { email, password }
   ```

2. **Upload Status**
   ```
   POST /api/status/upload
   Headers: Authorization: Bearer {token}
   Body (form-data): media, mediaType, caption
   ```

3. **Get Statuses**
   ```
   GET /api/status
   Headers: Authorization: Bearer {token}
   ```

4. **View Status**
   ```
   POST /api/status/:statusId/view
   Headers: Authorization: Bearer {token}
   ```

5. **Get Viewers**
   ```
   GET /api/status/:statusId/viewers
   Headers: Authorization: Bearer {token}
   ```

---

## 📱 Frontend Socket Connection

```javascript
import io from 'socket.io-client';

const socket = io('http://localhost:5000', {
  auth: {
    token: localStorage.getItem('token')
  }
});

// Listen for status events
socket.on('status:new', handleNewStatus);
socket.on('status:view-notification', handleViewNotification);
socket.on('status:deleted', handleStatusDeleted);
```

