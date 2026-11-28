/**
 * Comprehensive Automated Real-Time Communication & Call Lifecycle Integration Tests
 *
 * Tests against BOTH:
 *  - Live local Node.js + Socket.IO server at http://127.0.0.1:5006
 *  - MongoDB authoritative CallSession & Notification models
 *  - Live production transport endpoint at https://regen.krishub.in/ws/
 *
 * Run: node test_comm_realtime.js
 */
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import jwt from 'jsonwebtoken';
import mongoose from 'mongoose';
import WebSocket from 'ws';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '.env') });

import User from './models/User.js';
import Company from './models/Company.js';
import CallSession from './models/CallSession.js';
import Notification from './models/Notification.js';
import Conversation from './models/Conversation.js';
import DirectMessage from './models/DirectMessage.js';
import { createAndSendNotification } from './controllers/notificationController.js';
import { sendFcmPushToUsers, isFcmConfigured, initializeFcmStartup, getFcmStatus } from './utils/fcmPush.js';

const LOCAL_HTTP = 'http://127.0.0.1:5006';
const LOCAL_WS = 'ws://127.0.0.1:5006/ws/?EIO=4&transport=websocket';
const PROD_HTTP = 'https://regen.krishub.in';

let passed = 0;
let total = 0;

function assert(cond, name, details = '') {
  total++;
  if (cond) {
    passed++;
    console.log(`  \x1b[32m✔ [PASS]\x1b[0m ${name}`);
  } else {
    console.error(`  \x1b[31m✖ [FAIL]\x1b[0m ${name}${details ? ' — ' + details : ''}`);
  }
}

/**
 * Lightweight Engine.IO v4 / Socket.IO v4 WebSocket test client using `ws`.
 */
class SocketIoTestClient {
  constructor(url, authPayload) {
    this.url = url;
    this.authPayload = authPayload;
    this.ws = null;
    this.sid = null;
    this.connected = false;
    this.events = [];
    this.waiters = [];
    this.ackCounter = 1;
    this.ackCallbacks = new Map();
    this.authError = null;
  }

  connect(timeoutMs = 5000) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Socket connect timeout')), timeoutMs);
      this.ws = new WebSocket(this.url);

      this.ws.on('error', (err) => {
        clearTimeout(timer);
        reject(err);
      });

      this.ws.on('close', () => {
        this.connected = false;
      });

      this.ws.on('message', (raw) => {
        const msg = raw.toString();
        if (msg === '2') {
          if (this.ws.readyState === WebSocket.OPEN) this.ws.send('3');
          return;
        }
        if (msg.startsWith('0')) {
          this.ws.send(`40${JSON.stringify(this.authPayload)}`);
          return;
        }
        if (msg.startsWith('40')) {
          try {
            const parsed = JSON.parse(msg.slice(2));
            this.sid = parsed.sid || null;
          } catch (_) {}
          this.connected = true;
          clearTimeout(timer);
          resolve(this.sid);
          return;
        }
        if (msg.startsWith('44')) {
          try {
            this.authError = JSON.parse(msg.slice(2));
          } catch (_) {
            this.authError = { message: msg.slice(2) };
          }
          clearTimeout(timer);
          reject(new Error(`Socket auth error: ${this.authError?.message || msg}`));
          return;
        }
        if (msg.startsWith('43')) {
          const rest = msg.slice(2);
          const m = /^(\d+)(.*)$/.exec(rest);
          if (m) {
            const ackId = Number(m[1]);
            const args = JSON.parse(m[2]);
            const cb = this.ackCallbacks.get(ackId);
            if (cb) {
              this.ackCallbacks.delete(ackId);
              cb(args.length <= 1 ? args[0] : args);
            }
          }
          return;
        }
        if (msg.startsWith('42')) {
          const rest = msg.slice(2);
          const jsonStart = rest.indexOf('[');
          if (jsonStart >= 0) {
            try {
              const [event, data] = JSON.parse(rest.slice(jsonStart));
              this._pushEvent(event, data);
            } catch (_) {}
          }
        }
      });
    });
  }

  _pushEvent(event, data) {
    const entry = { event, data, ts: Date.now() };
    for (let i = 0; i < this.waiters.length; i++) {
      const w = this.waiters[i];
      if (w.event === event && (!w.predicate || w.predicate(data))) {
        this.waiters.splice(i, 1);
        clearTimeout(w.timer);
        w.resolve(data);
        return;
      }
    }
    this.events.push(entry);
  }

  emit(event, data) {
    this.ws.send(`42${JSON.stringify([event, data])}`);
  }

  emitAck(event, data, timeoutMs = 4000) {
    return new Promise((resolve, reject) => {
      const id = this.ackCounter++;
      const timer = setTimeout(() => {
        this.ackCallbacks.delete(id);
        reject(new Error(`Ack timeout for ${event}`));
      }, timeoutMs);
      this.ackCallbacks.set(id, (res) => {
        clearTimeout(timer);
        resolve(res);
      });
      this.ws.send(`42${id}${JSON.stringify([event, data])}`);
    });
  }

  waitFor(event, predicate = null, timeoutMs = 4000) {
    for (let i = 0; i < this.events.length; i++) {
      const e = this.events[i];
      if (e.event === event && (!predicate || predicate(e.data))) {
        this.events.splice(i, 1);
        return Promise.resolve(e.data);
      }
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const idx = this.waiters.findIndex((w) => w.timer === timer);
        if (idx >= 0) this.waiters.splice(idx, 1);
        reject(new Error(`Timed out waiting for socket event "${event}"`));
      }, timeoutMs);
      this.waiters.push({ event, predicate, resolve, reject, timer });
    });
  }

  clearEvents(eventName = null) {
    if (!eventName) {
      this.events = [];
    } else {
      this.events = this.events.filter((e) => e.event !== eventName);
    }
  }

  close() {
    if (this.ws) {
      try {
        this.ws.close();
      } catch (_) {}
      this.connected = false;
    }
  }
}

async function run() {
  console.log('\n==============================================================');
  console.log('   REGEN ALWAYS-READY MESSENGER & CALL LIFECYCLE TESTS');
  console.log('==============================================================\n');

  await mongoose.connect(process.env.MONGODB_URI);

  const suffix = `${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  const companyId = new mongoose.Types.ObjectId();
  const callerId = `COMM-TEST-CALLER-${suffix}`;
  const receiverId = `COMM-TEST-RECV-${suffix}`;
  const thirdUserId = `COMM-TEST-THIRD-${suffix}`;
  const otherCompanyId = new mongoose.Types.ObjectId();
  const outsiderId = `COMM-TEST-OUTSIDER-${suffix}`;
  const sharedDeviceToken = `fcm-shared-token-${suffix}`;

  const createdCallIds = [];
  let createdConvId = null;
  const socketsToClose = [];

  try {
    // Seed temporary test company & users
    await Company.create({
      _id: companyId,
      name: `Comm Test Co ${suffix}`,
      phoneNumber: '9999999999',
      city: 'Chennai',
      ownerId: callerId,
      status: 'active',
    });

    await User.insertMany([
      {
        userId: callerId,
        username: `caller_${suffix}`,
        name: 'Test Caller',
        role: 'staff',
        companyId,
        tokenVersion: 1,
      },
      {
        userId: receiverId,
        username: `receiver_${suffix}`,
        name: 'Test Receiver',
        role: 'staff',
        companyId,
        tokenVersion: 1,
      },
      {
        userId: thirdUserId,
        username: `third_${suffix}`,
        name: 'Test Third User',
        role: 'admin',
        companyId,
        tokenVersion: 1,
      },
      {
        userId: outsiderId,
        username: `outsider_${suffix}`,
        name: 'Test Outsider',
        role: 'staff',
        companyId: otherCompanyId,
        tokenVersion: 1,
      },
    ]);

    const signJwt = (userId, ver = 1, role = 'staff', compId = companyId) =>
      jwt.sign(
        {
          userId,
          id: userId,
          role,
          companyId: String(compId),
          tokenVersion: ver,
        },
        process.env.JWT_SECRET,
        { expiresIn: '1h' }
      );

    const callerJwt = signJwt(callerId);
    const receiverJwt = signJwt(receiverId);
    const thirdJwt = signJwt(thirdUserId, 1, 'admin');
    const outsiderJwt = signJwt(outsiderId, 1, 'staff', otherCompanyId);

    // 1. Verify live local server health & tokenVersion enforcement
    console.log('1. Server Auth, TokenVersion & Diagnostics:');
    const badJwt = signJwt(callerId, 99);
    const badClient = new SocketIoTestClient(LOCAL_WS, { token: badJwt, deviceId: 'bad-dev' });
    let badRejected = false;
    try {
      await badClient.connect(3000);
    } catch (e) {
      badRejected = /expired|revoked|auth/i.test(e.message);
    } finally {
      badClient.close();
    }
    assert(badRejected, 'Socket rejects mismatched tokenVersion (revoked/stale session)');

    const callerSock = new SocketIoTestClient(LOCAL_WS, { token: callerJwt, deviceId: 'caller-dev-1' });
    const receiverSock1 = new SocketIoTestClient(LOCAL_WS, { token: receiverJwt, deviceId: 'recv-dev-1' });
    const receiverSock2 = new SocketIoTestClient(LOCAL_WS, { token: receiverJwt, deviceId: 'recv-dev-2' });
    const thirdSock = new SocketIoTestClient(LOCAL_WS, { token: thirdJwt, deviceId: 'third-dev-1' });
    const outsiderSock = new SocketIoTestClient(LOCAL_WS, { token: outsiderJwt, deviceId: 'out-dev-1' });
    socketsToClose.push(callerSock, receiverSock1, receiverSock2, thirdSock, outsiderSock);

    await Promise.all([
      callerSock.connect(),
      receiverSock1.connect(),
      receiverSock2.connect(),
      thirdSock.connect(),
      outsiderSock.connect(),
    ]);
    assert(callerSock.connected && receiverSock1.connected && receiverSock2.connected, 'All legitimate clients connect immediately without opening Messenger');

    // Cross-company call isolation check
    const crossCallId = `call-cross-${suffix}`;
    createdCallIds.push(crossCallId);
    const crossAck = await outsiderSock.emitAck('call:initiate', {
      callId: crossCallId,
      recipientId: receiverId,
      mediaType: 'voice',
      offer: { sdp: 'v=0', type: 'offer' },
    });
    assert(crossAck && crossAck.ok === false, 'Cross-company call blocked by backend ACL');

    // 2. 12 consecutive calls WITHOUT any text messages sent
    console.log('\n2. Always-Ready Incoming Calls Without Text Messages (12 consecutive rounds):');
    let consecutiveOk = true;
    for (let i = 1; i <= 12; i++) {
      const callId = `call-consec-${suffix}-${i}`;
      createdCallIds.push(callId);
      receiverSock1.clearEvents('call:incoming');
      receiverSock2.clearEvents('call:incoming');
      callerSock.clearEvents('call:accepted');
      callerSock.clearEvents('call:rejected');
      callerSock.clearEvents('call:state');

      const initAck = await callerSock.emitAck('call:initiate', {
        callId,
        recipientId: receiverId,
        mediaType: i % 2 === 0 ? 'video' : 'voice',
        offer: { sdp: `fake-sdp-${i}`, type: 'offer' },
      });
      if (!initAck?.ok || initAck.state !== 'ringing') {
        consecutiveOk = false;
        break;
      }

      const [in1, in2] = await Promise.all([
        receiverSock1.waitFor('call:incoming', (d) => d.callId === callId),
        receiverSock2.waitFor('call:incoming', (d) => d.callId === callId),
      ]);
      if (in1.callId !== callId || in2.callId !== callId) {
        consecutiveOk = false;
        break;
      }

      receiverSock1.emit('call:ringing', { callId });
      await callerSock.waitFor('call:state', (d) => d.callId === callId && d.state === 'ringing');

      if (i % 3 === 1) {
        // Accept on dev-1 -> dev-2 gets call:state=accepted -> end call
        const acceptAck = await receiverSock1.emitAck('call:accept', {
          callId,
          callerId,
          answer: { sdp: `fake-ans-${i}`, type: 'answer' },
        });
        const [callerAcc, dev2Sync] = await Promise.all([
          callerSock.waitFor('call:accepted', (d) => d.callId === callId),
          receiverSock2.waitFor('call:state', (d) => d.callId === callId && d.state === 'accepted'),
        ]);
        if (!acceptAck?.ok || !callerAcc || dev2Sync.state !== 'accepted') {
          consecutiveOk = false;
          break;
        }
        callerSock.emit('call:end', { targetUserId: receiverId, callId });
        await receiverSock1.waitFor('call:ended', (d) => d.callId === callId);
      } else if (i % 3 === 2) {
        // Reject on dev-1 -> dev-2 stops ringing -> caller gets call:rejected
        receiverSock1.emit('call:reject', { callId, callerId, reason: 'declined' });
        await Promise.all([
          callerSock.waitFor('call:rejected', (d) => d.callId === callId),
          receiverSock2.waitFor('call:state', (d) => d.callId === callId && d.state === 'rejected'),
        ]);
      } else {
        // Caller cancels while ringing -> both receiver devices get call:cancelled
        callerSock.emit('call:end', { targetUserId: receiverId, callId });
        await Promise.all([
          receiverSock1.waitFor('call:cancelled', (d) => d.callId === callId),
          receiverSock2.waitFor('call:cancelled', (d) => d.callId === callId),
        ]);
      }
    }
    assert(consecutiveOk, '12 consecutive voice/video calls without opening chat or sending text (accept/reject/cancel + multi-device stop-ringing sync)');

    // 3. Busy check + terminal immutability + late signal guard
    console.log('\n3. Busy Guard, Authoritative States & Late Signal Protection:');
    const activeCallId = `call-busy-${suffix}`;
    createdCallIds.push(activeCallId);
    await callerSock.emitAck('call:initiate', {
      callId: activeCallId,
      recipientId: receiverId,
      mediaType: 'voice',
      offer: { sdp: 'sdp', type: 'offer' },
    });
    await receiverSock1.waitFor('call:incoming', (d) => d.callId === activeCallId);
    callerSock.emit('call:signal', {
      targetUserId: receiverId,
      callId: activeCallId,
      signal: { candidate: { candidate: 'candidate:1 1 UDP 2122252543 192.168.1.5 50000 typ host', sdpMid: '0', sdpMLineIndex: 0 } },
    });
    await new Promise((r) => setTimeout(r, 80));
    const activeMeta = await receiverSock1.emitAck('call:get-active', { callId: activeCallId });
    assert(
      Array.isArray(activeMeta?.callerCandidates) && activeMeta.callerCandidates.length >= 1,
      'call:get-active returns buffered caller ICE candidates for background/wakeup recovery'
    );

    await receiverSock1.emitAck('call:accept', { callId: activeCallId, callerId, answer: { sdp: 'ans', type: 'answer' } });
    await callerSock.waitFor('call:accepted', (d) => d.callId === activeCallId);
    receiverSock1.emit('call:signal', {
      targetUserId: callerId,
      callId: activeCallId,
      signal: { candidate: { candidate: 'candidate:2 1 UDP 2122252543 192.168.1.6 50001 typ host', sdpMid: '0', sdpMLineIndex: 0 } },
    });
    await new Promise((r) => setTimeout(r, 80));

    const busyCallId = `call-busy2-${suffix}`;
    createdCallIds.push(busyCallId);
    const busyAck = await thirdSock.emitAck('call:initiate', {
      callId: busyCallId,
      recipientId: receiverId,
      mediaType: 'voice',
      offer: { sdp: 'sdp2', type: 'offer' },
    });
    assert(busyAck?.ok === false && busyAck?.reason === 'busy', 'Third caller calling busy receiver receives immediate busy rejection');

    // Now test multi-device disconnect during active call: receiverSock2 disconnects, active call survives!
    receiverSock2.close();
    await new Promise((r) => setTimeout(r, 150));
    const syncWhileActive = await receiverSock1.emitAck('call:sync', { callId: activeCallId });
    const callerSyncActive = await callerSock.emitAck('call:sync', { callId: activeCallId });
    assert(syncWhileActive?.ok && syncWhileActive?.state === 'accepted', 'Secondary device disconnect does NOT drop active accepted call on primary device');
    assert(
      callerSyncActive?.ok &&
        callerSyncActive?.state === 'accepted' &&
        callerSyncActive?.answer?.sdp === 'ans' &&
        Array.isArray(callerSyncActive?.recipientCandidates) &&
        callerSyncActive.recipientCandidates.length >= 1,
      'call:sync returns authoritative SDP answer and buffered ICE candidates to caller for accepted call recovery'
    );

    // End activeCallId and verify terminal immutability
    callerSock.emit('call:end', { targetUserId: receiverId, callId: activeCallId });
    await receiverSock1.waitFor('call:ended', (d) => d.callId === activeCallId);

    const lateAcceptAck = await receiverSock1.emitAck('call:accept', { callId: activeCallId, callerId, answer: { sdp: 'late', type: 'answer' } });
    const reinitAck = await callerSock.emitAck('call:initiate', { callId: activeCallId, recipientId: receiverId, mediaType: 'voice', offer: { sdp: 'late', type: 'offer' } });
    assert(lateAcceptAck?.ok === false && reinitAck?.ok === false && reinitAck?.reason === 'already_terminal', 'Terminal call rejects late accept & re-initiation attempts');

    // 4. Reconnect / offline->online pending call recovery via call:sync & auto-sync
    console.log('\n4. Offline -> Reconnect Pending Call Synchronization:');
    receiverSock1.close();
    await new Promise((r) => setTimeout(r, 150));

    const offlineCallId = `call-offline-${suffix}`;
    createdCallIds.push(offlineCallId);
    const offlineInitAck = await callerSock.emitAck('call:initiate', {
      callId: offlineCallId,
      recipientId: receiverId,
      mediaType: 'video',
      offer: { sdp: 'sdp-offline', type: 'offer' },
    });
    assert(offlineInitAck?.ok && offlineInitAck?.state === 'initiated', 'Calling offline receiver persists CallSession in initiated state');

    const reconnectedRecv = new SocketIoTestClient(LOCAL_WS, { token: receiverJwt, deviceId: 'recv-dev-reconn' });
    socketsToClose.push(reconnectedRecv);
    await reconnectedRecv.connect();
    const recoveredIncoming = await reconnectedRecv.waitFor('call:incoming', (d) => d.callId === offlineCallId);
    const syncResp = await reconnectedRecv.emitAck('call:sync', { callId: offlineCallId });
    assert(
      recoveredIncoming?.callId === offlineCallId && syncResp?.state === 'ringing',
      'Reconnected receiver automatically receives pending incoming call & call:sync transitions to ringing'
    );
    const ringingBusyCallId = `call-ring-busy-${suffix}`;
    createdCallIds.push(ringingBusyCallId);
    const ringingBusyAck = await thirdSock.emitAck('call:initiate', {
      callId: ringingBusyCallId,
      recipientId: receiverId,
      mediaType: 'voice',
      offer: { sdp: 'sdp-busy', type: 'offer' },
    });
    assert(
      ringingBusyAck?.ok === false && ringingBusyAck?.reason === 'busy',
      'Calling a participant with an active ringing call fails fast with reason="busy"'
    );

    callerSock.emit('call:end', { targetUserId: receiverId, callId: offlineCallId });
    await reconnectedRecv.waitFor('call:cancelled', (d) => d.callId === offlineCallId);
    const missedNotifSock = await reconnectedRecv.waitFor(
      'notification:new',
      (d) => d?.type === 'missed_call' && d?.callId === offlineCallId
    );

    const cancelDb = await CallSession.findOne({ callId: offlineCallId }).lean();
    const missedDb = await Notification.findOne({ id: `missed-${offlineCallId}` }).lean();
    assert(cancelDb?.state === 'cancelled', 'Cancelled pending call persists authoritative state="cancelled" in MongoDB');
    assert(
      Boolean(missedNotifSock && missedDb && missedDb.type === 'missed_call' && missedDb.senderId === callerId),
      'Cancelled pending call emits & persists deterministic missed-${callId} notification for receiver'
    );

    // 5. Real-time DM & per-socket active-conversation tracking
    console.log('\n5. Direct Messages & Multi-Device Active-Chat Notification Suppression:');
    const createConvResp = await fetch(`${LOCAL_HTTP}/api/dm/conversations`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${callerJwt}` },
      body: JSON.stringify({ recipientId: receiverId }),
    });
    const convJson = await createConvResp.json();
    createdConvId = String(convJson?._id || convJson?.conversation?._id || '');
    assert(Boolean(createdConvId), 'Direct conversation created via authenticated API');

    if (createdConvId) {
      const dmRecv2 = new SocketIoTestClient(LOCAL_WS, { token: receiverJwt, deviceId: 'recv-chat-2' });
      socketsToClose.push(dmRecv2);
      await dmRecv2.connect();

      reconnectedRecv.emit('dm:join-conversation', { conversationId: createdConvId });
      dmRecv2.emit('dm:join-conversation', { conversationId: createdConvId });
      await new Promise((r) => setTimeout(r, 100));
      dmRecv2.close(); // One tab/device closes while primary device still has chat open!
      await new Promise((r) => setTimeout(r, 100));

      reconnectedRecv.clearEvents('dm:change');
      reconnectedRecv.clearEvents('notification:new');
      callerSock.clearEvents('dm:change');
      await fetch(`${LOCAL_HTTP}/api/dm/conversations/${createdConvId}/messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${callerJwt}` },
        body: JSON.stringify({ content: 'hello-active-check', type: 'text' }),
      });
      const gotDmWhileActive = await reconnectedRecv.waitFor('dm:change', (d) => d?.action === 'create' && d?.message?.content === 'hello-active-check');
      await new Promise((r) => setTimeout(r, 250));
      const suppressedNotif = reconnectedRecv.events.find((e) => e.event === 'notification:new' && e.data?.conversationId === createdConvId);
      const extraCreateDupCount = reconnectedRecv.events.filter((e) => e.event === 'dm:change' && e.data?.action === 'create' && e.data?.message?.content === 'hello-active-check').length;
      assert(Boolean(gotDmWhileActive) && !suppressedNotif, 'Second device disconnect does not wipe primary active-conversation suppression');
      assert(extraCreateDupCount === 0, 'dm:change create is delivered once without room+participant duplication');
      assert(
        Array.isArray(gotDmWhileActive?.message?.readBy) &&
          gotDmWhileActive.message.readBy.length === 1 &&
          gotDmWhileActive.message.readBy[0] === callerId,
        'Server does NOT pre-mark message read before receiver client acknowledges rendering it'
      );
      reconnectedRecv.emit('dm:read', { conversationId: createdConvId });
      const readReceiptForCaller = await callerSock.waitFor('dm:change', (d) => d?.action === 'read' && d?.conversationId === createdConvId);
      assert(readReceiptForCaller?.userId === receiverId, 'Receiver explicit dm:read delivers blue-tick read receipt to caller');

      // Verify x-skip-auto-read: 1 (Flutter REST fetch) preserves unread state, whereas Chrome-style GET /messages marks read & emits read receipt
      callerSock.clearEvents('dm:change');
      await fetch(`${LOCAL_HTTP}/api/dm/conversations/${createdConvId}/messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${callerJwt}` },
        body: JSON.stringify({ content: 'hello-chrome-read-check', type: 'text' }),
      });
      await reconnectedRecv.waitFor('dm:change', (d) => d?.action === 'create' && d?.message?.content === 'hello-chrome-read-check');
      const skipReadResp = await fetch(`${LOCAL_HTTP}/api/dm/conversations/${createdConvId}/messages`, {
        headers: { Authorization: `Bearer ${receiverJwt}`, 'x-skip-auto-read': '1' },
      });
      const skipReadList = await skipReadResp.json();
      const targetSkipMsg = Array.isArray(skipReadList) ? skipReadList.find((m) => m.content === 'hello-chrome-read-check') : null;
      assert(
        Array.isArray(targetSkipMsg?.readBy) && !targetSkipMsg.readBy.includes(receiverId),
        'GET /messages with x-skip-auto-read: 1 does NOT prematurely mark unread messages read'
      );

      callerSock.clearEvents('dm:change');
      const chromeReadResp = await fetch(`${LOCAL_HTTP}/api/dm/conversations/${createdConvId}/messages`, {
        headers: { Authorization: `Bearer ${receiverJwt}` },
      });
      const chromeReadList = await chromeReadResp.json();
      const targetChromeMsg = Array.isArray(chromeReadList) ? chromeReadList.find((m) => m.content === 'hello-chrome-read-check') : null;
      const chromeReadReceipt = await callerSock.waitFor('dm:change', (d) => d?.action === 'read' && d?.conversationId === createdConvId);
      assert(
        Array.isArray(targetChromeMsg?.readBy) &&
          targetChromeMsg.readBy.includes(receiverId) &&
          chromeReadReceipt?.userId === receiverId,
        'Chrome-style GET /messages (active thread fetch) marks read and delivers blue-tick read receipt to Flutter sender'
      );

      // Clear active conversation -> next DM generates both dm:change AND notification:new
      reconnectedRecv.emit('dm:leave-conversation', { conversationId: createdConvId });
      await new Promise((r) => setTimeout(r, 100));
      await fetch(`${LOCAL_HTTP}/api/dm/conversations/${createdConvId}/messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${callerJwt}` },
        body: JSON.stringify({ content: 'hello-bg-check', type: 'text' }),
      });
      const gotDmBg = await reconnectedRecv.waitFor('dm:change', (d) => d?.action === 'create' && d?.message?.content === 'hello-bg-check');
      const gotNotifBg = await reconnectedRecv.waitFor('notification:new', (d) => d?.conversationId === createdConvId);
      assert(Boolean(gotDmBg) && Boolean(gotNotifBg), 'DM when Messenger is closed delivers real-time dm:change + notification:new');

      // Video multipart upload + rich notification content + notification read_all socket sync
      const form = new FormData();
      form.append('file', new Blob([Buffer.from('fake-mp4-stream')], { type: 'video/mp4' }), 'site-walkthrough.mp4');
      const uploadResp = await fetch(`${LOCAL_HTTP}/api/dm/upload`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${callerJwt}` },
        body: form,
      });
      const uploadJson = await uploadResp.json().catch(() => ({}));
      assert(
        uploadResp.status === 201 && String(uploadJson?.path || '').startsWith('/assets/dm-video-'),
        'POST /api/dm/upload stores multipart video file and returns /assets/ path'
      );

      reconnectedRecv.clearEvents('notification:new');
      await fetch(`${LOCAL_HTTP}/api/dm/conversations/${createdConvId}/messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${callerJwt}` },
        body: JSON.stringify({
          content: '',
          attachments: uploadJson?.path ? [uploadJson] : [{ path: '/assets/demo-video.mp4', name: 'demo.mp4', type: 'video/mp4', size: 15 }],
        }),
      });
      const videoNotif = await reconnectedRecv.waitFor('notification:new', (d) => d?.conversationId === createdConvId);
      assert(
        String(videoNotif?.message || '').toLowerCase().includes('sent a video'),
        'Video DM notification carries specific sender + video context (no generic attachment text)'
      );

      reconnectedRecv.clearEvents('notification:read_all');
      await fetch(`${LOCAL_HTTP}/api/notifications/user/${receiverId}/read-all`, {
        method: 'PUT',
        headers: { Authorization: `Bearer ${receiverJwt}` },
      });
      const readAllEv = await reconnectedRecv.waitFor('notification:read_all', () => true);
      assert(Boolean(readAllEv), 'PUT /read-all emits notification:read_all for live badge synchronization');

      // Authenticated Media Download Security & Integrity Tests (Feature 4)
      if (uploadJson?.path) {
        const fname = encodeURIComponent(uploadJson.path.split('/').pop());
        const unauthDl = await fetch(`${LOCAL_HTTP}/api/dm/media/${fname}?download=1`);
        const nonParticipantDl = await fetch(`${LOCAL_HTTP}/api/dm/media/${fname}?download=1`, {
          headers: { Authorization: `Bearer ${thirdJwt}` },
        });
        const authDl = await fetch(`${LOCAL_HTTP}/api/dm/media/${fname}?download=1`, {
          headers: { Authorization: `Bearer ${receiverJwt}` },
        });
        const authBody = await authDl.text();
        assert(
          unauthDl.status === 401 &&
            nonParticipantDl.status === 403 &&
            authDl.status === 200 &&
            String(authDl.headers.get('content-disposition') || '').includes('attachment') &&
            authBody === 'fake-mp4-stream',
          'GET /api/dm/media/:filename enforces JWT auth + conversation isolation and streams intact media bytes'
        );

        try {
          const fsMod = await import('fs');
          const pathMod = await import('path');
          const fp = pathMod.default.resolve(process.cwd(), '..', 'assets', pathMod.default.basename(uploadJson.path));
          if (fsMod.default.existsSync(fp)) fsMod.default.unlinkSync(fp);
        } catch (_) {}
      }

      // Group call meeting:get-active + join + signal relay check
      const mtgId = `mtg-test-${suffix}`;
      callerSock.emit('meeting:start', {
        meetingId: mtgId,
        title: 'Design Sync',
        mediaType: 'video',
        participantIds: [receiverId],
      });
      const mtgInvite = await reconnectedRecv.waitFor('meeting:started', (d) => d?.meetingId === mtgId);
      const mtgActive = await reconnectedRecv.emitAck('meeting:get-active', { meetingId: mtgId });
      callerSock.emit('meeting:join', { meetingId: mtgId, userInfo: { userId: callerId, username: 'Caller' } });
      await new Promise((r) => setTimeout(r, 80));
      reconnectedRecv.emit('meeting:join', { meetingId: mtgId, userInfo: { userId: receiverId, username: 'Receiver' } });
      const existingUsersEv = await reconnectedRecv.waitFor('meeting:existing-users', (d) => d?.meetingId === mtgId);
      reconnectedRecv.clearEvents('meeting:signal');
      callerSock.emit('meeting:signal', {
        meetingId: mtgId,
        targetUserId: receiverId,
        signal: { type: 'offer', offer: { type: 'offer', sdp: 'v=0\r\nmock-group-offer' } },
      });
      const relayedMtgSig = await reconnectedRecv.waitFor('meeting:signal', (d) => d?.meetingId === mtgId && d?.fromUserId === callerId);
      assert(
        Boolean(mtgInvite) &&
          mtgActive?.meetingId === mtgId &&
          mtgActive?.mediaType === 'video' &&
          Array.isArray(existingUsersEv?.users) &&
          relayedMtgSig?.signal?.type === 'offer',
        'meeting:get-active returns metadata and group call join/signal relay works cleanly'
      );
      callerSock.emit('meeting:leave', { meetingId: mtgId });
      reconnectedRecv.emit('meeting:leave', { meetingId: mtgId });
    }

    // 6. FCM device-token cross-account cleanup & diagnostics endpoint
    console.log('\n6. FCM Device Token Isolation, Graceful Unconfigured Handling & Diagnostics:');
    await fetch(`${LOCAL_HTTP}/api/notifications/device-token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${callerJwt}` },
      body: JSON.stringify({ userId: callerId, token: sharedDeviceToken, platform: 'android', deviceId: 'shared-phone' }),
    });
    await fetch(`${LOCAL_HTTP}/api/notifications/device-token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${receiverJwt}` },
      body: JSON.stringify({ userId: receiverId, token: sharedDeviceToken, platform: 'android', deviceId: 'shared-phone' }),
    });
    const callerDoc = await User.findOne({ userId: callerId }).lean();
    const recvDoc = await User.findOne({ userId: receiverId }).lean();
    assert(
      !callerDoc?.pushTokens?.some((t) => t.token === sharedDeviceToken) &&
        recvDoc?.pushTokens?.some((t) => t.token === sharedDeviceToken),
      'Registering shared device FCM token removes token from previous account on same phone'
    );

    const pushGraceful = await sendFcmPushToUsers({
      userIds: [receiverId],
      title: 'Test',
      body: 'Test',
      data: { type: 'voice_call', callId: 'dryrun' },
      dataOnly: true,
    });
    assert(
      pushGraceful && typeof pushGraceful.configured === 'boolean' && pushGraceful.configured === isFcmConfigured(),
      `FCM dispatcher reports configured=${pushGraceful.configured} without crashing`
    );

    const diagResp = await fetch(`${LOCAL_HTTP}/api/notifications/diagnostics`, {
      headers: { Authorization: `Bearer ${thirdJwt}` },
    });
    const diagJson = await diagResp.json();
    assert(
      diagResp.status === 200 && diagJson?.socket?.initialized === true && Array.isArray(diagJson?.recentEvents),
      'GET /api/notifications/diagnostics (admin) returns live socket state, fcm status, and redacted event log'
    );

    const staffDiagResp = await fetch(`${LOCAL_HTTP}/api/notifications/diagnostics`, {
      headers: { Authorization: `Bearer ${callerJwt}` },
    });
    const staffDiagJson = await staffDiagResp.json();
    assert(
      staffDiagResp.status === 200 &&
        staffDiagJson?.socket?.connectedUsers === undefined &&
        Array.isArray(staffDiagJson?.recentEvents) &&
        staffDiagJson.recentEvents.length === 0,
      'GET /api/notifications/diagnostics (staff) redacts user socket map and internal event history'
    );

    const unauthTokenResp = await fetch(`${LOCAL_HTTP}/api/notifications/device-token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: 'unauth-token' }),
    });
    assert(unauthTokenResp.status === 401, 'Unauthenticated POST /api/notifications/device-token rejected with 401');

    // 7. FCM Credential Validation, Startup Diagnostics & Notification Idempotency
    console.log('\n7. FCM Credential Validation, Notification Types & MongoDB Deduplication:');
    const prevJsonEnv = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    const prevPathEnv = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
    try {
      delete process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
      process.env.FIREBASE_SERVICE_ACCOUNT_JSON = '{invalid-json';
      const badBoot = initializeFcmStartup({ forceReload: true });
      assert(badBoot.configured === false && Boolean(badBoot.error), 'Invalid FIREBASE_SERVICE_ACCOUNT_JSON fails safely without pretending configured');

      process.env.FIREBASE_SERVICE_ACCOUNT_JSON = JSON.stringify({
        type: 'service_account',
        project_id: 'regen-929cc',
        client_email: 'firebase-adminsdk-test@regen-929cc.iam.gserviceaccount.com',
        private_key: '-----BEGIN PRIVATE KEY-----\nTEST-SYNTHETIC-KEY-NOT-REAL\n-----END PRIVATE KEY-----\n',
      });
      const goodBoot = initializeFcmStartup({ forceReload: true });
      const safeStatus = getFcmStatus();
      assert(
        goodBoot.configured === true &&
          goodBoot.projectId === 'regen-929cc' &&
          !JSON.stringify(safeStatus).includes('TEST-SYNTHETIC-KEY-NOT-REAL'),
        'Valid service account validates project_id and NEVER exposes private_key in getFcmStatus()'
      );
    } finally {
      if (prevJsonEnv !== undefined) process.env.FIREBASE_SERVICE_ACCOUNT_JSON = prevJsonEnv;
      else delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
      if (prevPathEnv !== undefined) process.env.FIREBASE_SERVICE_ACCOUNT_PATH = prevPathEnv;
      initializeFcmStartup({ forceReload: true });
    }

    const dedupNotifId = `dedup-test-${suffix}`;
    await createAndSendNotification({
      id: dedupNotifId,
      companyId,
      userId: receiverId,
      title: 'Leave Approved',
      message: 'Deduplication check',
      type: 'leave',
    });
    await createAndSendNotification({
      id: dedupNotifId,
      companyId,
      userId: receiverId,
      title: 'Leave Approved',
      message: 'Deduplication check',
      type: 'leave',
    });
    const dedupCount = await Notification.countDocuments({ id: dedupNotifId });
    assert(dedupCount === 1, 'createAndSendNotification deduplicates duplicate notification IDs in MongoDB');

    const missedEnumNotif = await createAndSendNotification({
      id: `missed-enum-${suffix}`,
      companyId,
      userId: receiverId,
      title: 'Missed Voice Call',
      message: 'Test Caller called you',
      type: 'missed_call',
      callId: `missed-call-enum-${suffix}`,
    });
    assert(Boolean(missedEnumNotif && missedEnumNotif.type === 'missed_call'), 'Notification model accepts and persists missed_call enum cleanly');

    // 8. Live Production Socket.IO Handshake & Diagnostics Verification
    console.log('\n8. Production Environment (https://regen.krishub.in) Verification:');
    try {
      const prodPoll = await fetch(`${PROD_HTTP}/ws/?EIO=4&transport=polling`);
      const prodText = await prodPoll.text();
      assert(prodPoll.status === 200 && prodText.startsWith('0{'), `Production Socket.IO Engine.IO v4 handshake 200 OK (sid returned)`);
    } catch (e) {
      assert(false, 'Production Socket.IO handshake reachable', e.message);
    }

    console.log(`\n--------------------------------------------------------------`);
    console.log(`  RESULT: ${passed}/${total} tests passed`);
    console.log(`--------------------------------------------------------------\n`);
    process.exitCode = passed === total ? 0 : 1;
  } finally {
    for (const s of socketsToClose) s.close();
    await Promise.all([
      createdCallIds.length ? CallSession.deleteMany({ callId: { $in: createdCallIds } }) : null,
      createdCallIds.length ? Notification.deleteMany({ callId: { $in: createdCallIds } }) : null,
      createdConvId ? DirectMessage.deleteMany({ conversationId: createdConvId }) : null,
      createdConvId ? Conversation.deleteOne({ _id: createdConvId }) : null,
      Notification.deleteMany({ userId: { $in: [callerId, receiverId, thirdUserId, outsiderId] } }),
      User.deleteMany({ userId: { $in: [callerId, receiverId, thirdUserId, outsiderId] } }),
      Company.deleteOne({ _id: companyId }),
    ]);
    await mongoose.disconnect();
  }
}

run().catch((err) => {
  console.error('Fatal test suite error:', err);
  process.exit(1);
});
