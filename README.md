# inminutes — Flutter frontend

Flutter client for the **inminutes** collaborative food ordering backend.

Order on your own, or open a **group session** where several people share one
cart in real time — adding items, seeing each other's changes live, marking
themselves ready, and having the host check out for everyone.

Backend: [`../inminutes_backend`](../inminutes_backend) (Express + MongoDB +
socket.io).

---

## What it does

**Getting in**

- First run asks for a username and creates the user — no password, no login
- Already have one? Switch to **I have one** and type the username to continue
  as that user. It is a demo shortcut, not authentication: the name is matched
  against `/api/users` with nothing to verify it

**Individual ordering** (the default mode)

- Browse the menu with live stock on every item
- Add to a personal cart, change quantity, remove — the card updates in the
  same frame as the tap, then reconciles with the server
- The cart is always one tap away: a badged icon at the top of the home
  screen, plus a summary bar at the bottom once it has something in it
- Place an order and see the order history

**Group ordering** (one tap from the top of the home screen)

- Host creates a session and gets an 8-character join code
- Others join with that code and a display name
- Anyone already in the session — the host included — can back out and walk
  straight back in from the join-code button on the home screen
- Everyone shares one cart, shown as **one basket per person**. Two people
  ordering the same dish each keep their own line and quantity, so you can see
  who wanted what instead of one merged number
- Changes made by one person appear on everyone else's device instantly
- Participants toggle Ready / Not Ready
- The host can **remove a participant**, which also frees the stock that member
  was holding in the shared cart
- The host's **Place order** button only enables once the backend says every
  participant is ready
- Placing the order closes the session, live, on every device
- The host gets a **log of every group they hosted**, with a breakdown of who
  ordered what and what each person owes

**Stock, throughout**

Stock is reserved by the backend the moment something enters any cart. If
someone takes the last unit, every other device sees it turn to *Sold out*
without a refresh; if they remove it, it comes back.

---

## Versions

| | |
|---|---|
| Flutter | 3.41.2 (stable) |
| Dart | 3.11.0 |
| Android compileSdk / targetSdk | 36 |
| Android minSdk | 24 |
| Java | 17 |
| UI | Material 3, AndroidX |

Built and tested with the Android SDK 36.1.0 toolchain.

---

## Setup

### 1. Run the backend first

```bash
cd ../inminutes_backend
npm install
npm run seed      # ~17 demo products, incl. low-stock and zero-stock items
npm run dev       # http://localhost:3000
```

### 2. Run the app

```bash
flutter pub get
flutter run
```

### 3. Point the app at your backend

The backend URL lives in exactly one place —
[lib/utils/config.dart](lib/utils/config.dart) — and is overridable without
editing code:

```dart
static const String serverUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://10.0.2.2:3000',
);
static const String apiBaseUrl = '$serverUrl/api';
```

| Where the app runs | What to pass |
|---|---|
| Android emulator | nothing — `10.0.2.2` is the default, and is the emulator's alias for your machine's `localhost` |
| Real phone on the same Wi-Fi | `--dart-define=SERVER_URL=http://192.168.x.x:3000` |
| Real phone through a dev tunnel | `--dart-define=SERVER_URL=https://your-tunnel-url` |
| Chrome / desktop | `--dart-define=SERVER_URL=http://localhost:3000` |

```bash
flutter run --dart-define=SERVER_URL=http://192.168.1.20:3000
```

REST calls use `apiBaseUrl` (`.../api`); Socket.IO connects to `serverUrl`
(no `/api`). Both derive from the same value, so there is one thing to change.

> The default backend is plain `http://`, so the Android manifest sets
> `android:usesCleartextTraffic="true"` alongside the `INTERNET` permission.
> Drop the cleartext flag if you move to an https-only tunnel.

---

## Build an APK

```bash
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk
```

Baking in a tunnel URL so the APK works off your dev machine:

```bash
flutter build apk --release --dart-define=SERVER_URL=https://your-tunnel-url
```

Smaller, per-architecture APKs:

```bash
flutter build apk --release --split-per-abi
```

The release build is signed with the debug keys (Flutter's template default),
which is fine for an assignment build but not for distribution.

---

## Packages used

Four, each earning its place.

| Package | Why it is used |
|---|---|
| [`provider`](https://pub.dev/packages/provider) ^6.1.5 | State management. `ChangeNotifier` + `Consumer`/`Selector` is the lightest thing that lets a socket event rebuild just the cart list instead of the whole screen. |
| [`http`](https://pub.dev/packages/http) ^1.6.0 | REST calls. Dart's official client; no need for Dio's interceptors, retries or cancellation here. |
| [`socket_io_client`](https://pub.dev/packages/socket_io_client) ^3.1.6 | The backend speaks Socket.IO 4.8, which is a protocol on top of WebSocket — a raw `WebSocket` cannot talk to it. Version 3.x matches Engine.IO 4. |
| [`shared_preferences`](https://pub.dev/packages/shared_preferences) ^2.5.5 | Stores the created user id so the app does not ask for a name on every restart. Two strings; a database would be overkill. |

Deliberately **not** added: a router (`Navigator.push` is enough), a DI
container, a codegen/serialization package (`fromJson` by hand is ~10 lines per
model), a state machine, or an HTTP wrapper on top of the HTTP package.

---

## Design

The visual direction comes from the supplied UI reference: a deep violet brand
surface with a lime accent, bold italic uppercase typography, generously
rounded tinted cards, and a price pill on each product tile.

| Token | Value | Used for |
|---|---|---|
| Violet | `#4F1BD1` | brand surfaces, buttons, prices, steppers |
| Lime | `#D4FF3F` | the accent — only ever on violet |
| Violet soft | `#F0EBFF` | product card bodies |
| Background | `#F5F4F7` | page background |
| Grey | `#DCDCE2` / `#9A9AA4` | out-of-stock cards and buttons |

Every one of those lives in [lib/utils/app_theme.dart](lib/utils/app_theme.dart)
and nowhere else, so re-skinning the app is a one-file change.

Two rules keep it readable rather than merely loud: **lime never appears on a
light background** (it is used only on the violet header CTA and the group
screen's LIVE badge), and **out-of-stock items go grey** — grey card, grey
initial, and a disabled `NO STOCK` button in place of `ADD` — mirroring the
reference's desaturated tiles.

Following the brief, the styling stops there: no gradients, no custom painters,
no animation beyond Material's own transitions. The reference's struck-through
list price and marketing copy are not reproduced, because the backend has no
such fields and inventing them would be inventing data.

---

## Architecture

```
lib/
├── main.dart              app entry, providers, first-screen routing
├── models/                plain data classes with fromJson
├── services/              api_service.dart (REST), socket_service.dart (Socket.IO)
├── state/                 three ChangeNotifiers
├── screens/               one file per screen
├── widgets/               widgets shared by more than one screen
└── utils/                 config.dart, app_theme.dart, ui.dart
```

One rule holds the whole thing together:

```
Widget  ->  ChangeNotifier  ->  ApiService / SocketService  ->  backend
   ^                |
   +-- notifyListeners() --+
```

No repository layer, no use cases, no service locator, no
domain/data/presentation split. A screen is a widget, a network call is a
method on `ApiService`, and shared state is a `ChangeNotifier`.

`lib/utils/config.dart` is the only file that knows the backend address and
`lib/utils/app_theme.dart` is the only file that defines colours, radii and
spacing.

---

## State management

`provider` + `ChangeNotifier`. Three notifiers, each with one clear owner.

| Notifier | Lives | Owns |
|---|---|---|
| `UserState` | app root | the current user id/name and its SharedPreferences persistence |
| `ShopState` | app root | the product list and the personal cart |
| `GroupState` | the group route only | one group session and its socket |

`GroupState` is deliberately **not** global. It is created by the
`ChangeNotifierProvider` inside `GroupScreen.route(...)`, so the socket
connects when the group screen opens and is disposed when it closes. There is
no app-wide socket lifetime to reason about.

`GroupState` takes `ShopState` in its constructor so that when a group event
arrives it can also refresh the product list — that is what makes another
person's reservation appear as *Sold out* on the group menu.

### Keeping rebuilds small, and the scroll where it was

The assignment cares about this, so it is enforced by structure rather than by
discipline:

- Screens are `StatefulWidget`s that own their `ScrollController`. A socket
  event never recreates the screen, the controller, or the list.
- Realtime updates flow through `Consumer`/`Selector` wrapped around the
  smallest subtree that shows the changed data.
- `ListView.builder` / `ListView` children rebuild in place, so a `group:state`
  arriving mid-scroll leaves the offset alone.
- Nothing ever calls `pushReplacement` on the current screen to "refresh" it.

---

## Socket.IO synchronization

```
Flutter  --connect-->  Socket.IO  --emit "group:join" <joinCode>-->  backend room
                                  <--"group:state" (full session)----
```

The design has three rules, all of which come from the backend's own model:

1. **The client never writes over the socket.** Every mutation is an ordinary
   REST call. The socket exists only to deliver the result to everyone else, so
   validation lives in exactly one place — the server.
2. **There is one server event, `group:state`,** and its payload is the
   *complete* group session. `GroupState` replaces its copy wholesale. No
   diffing, no merge logic, no fine-grained `cart:item_added` events.
3. **`group:join` is re-emitted on every `connect`,** so a reconnect
   re-subscribes by itself. The app bar shows *Live* / *Connecting* from the
   socket's own connection callbacks.

`transports: ['websocket']` — the polling upgrade adds nothing here and is
flaky through dev tunnels.

`group:state` arrives after any of: a participant joins, an item is added to
the group cart, a quantity changes, an item is removed, someone toggles ready,
or the host places the order (the final broadcast, with `active: false`).

Because each group cart line embeds the product's live `qty`/`instock`, stock
updates ride along on the same event.

---

## Group order flow

```
Home
 └─ Group Order
     ├─ Create group ──────────────► POST /api/group-sessions        → join code
     │                                                                    │
     └─ Join with code + name ─────► POST /api/group-sessions/:code/join  │
                                                                          ▼
                                                            Group session screen
                                                        (connects the socket here)
                                                                          │
                          ┌───────────────────────────────────────────────┤
                          │                                               │
              Add items from the menu                          Participants mark Ready
       POST/PATCH/DELETE .../cart                PATCH .../participants/:userId/ready
                          │                                               │
                          └──────────────► group:state to every device ◄──┘
                                                                          │
                                                        Host: Place order │
                                    POST /api/group-sessions/:code/order  ▼
                                                    session closed (active: false)
```

The host is never a participant and has no Ready flag, matching the backend —
"everyone is ready" only ever refers to the people who joined.

---

## API endpoints integrated

All of them, taken from the backend source rather than guessed.

| Method | Path |
|---|---|
| GET · POST | `/api/users` |
| GET | `/api/users/:userId` |
| GET | `/api/products` |
| GET · POST | `/api/users/:userId/cart` |
| PATCH · DELETE | `/api/users/:userId/cart/:productId` |
| GET · POST | `/api/users/:userId/orders` |
| GET | `/api/users/:userId/group-orders` (host's log + split) |
| POST | `/api/group-sessions` (optional host `display_name`) |
| GET | `/api/group-sessions/:joinCode` |
| POST | `/api/group-sessions/:joinCode/join` |
| PATCH | `/api/group-sessions/:joinCode/participants/:userId/ready` |
| DELETE | `/api/group-sessions/:joinCode/participants/:participantId` (host only) |
| POST | `/api/group-sessions/:joinCode/cart` |
| PATCH · DELETE | `/api/group-sessions/:joinCode/cart/:productId` |
| POST | `/api/group-sessions/:joinCode/order` |

Socket.IO: emits `group:join` / `group:leave`, listens for `group:state` and
`group:participant_removed`.

### Error handling

`ApiService` throws `ApiException(statusCode, message)`. The backend's own
wording is used when there is any — so a user sees *"Insufficient stock"* or
*"Display name already exists in this group"*, not a status code. Otherwise a
short fallback is derived from the status (`403` → "You are not allowed to do
that.", network failure → "Cannot reach the server. Check your connection.").
A `500` always shows the generic fallback, never the backend's own body text —
that status is developer-facing by definition. Two 409 messages that reference
the backend's own HTTP verbs (`"...use PATCH..."`) are rewritten to plain
English before a widget ever sees them; every other backend message reaches
the user unchanged. Raw exceptions and stack traces never reach the UI.

---

## Endpoints deliberately not called

Three of the documented endpoints are unused, because the client already has
what they return:

| Endpoint | Why not |
|---|---|
| `GET /api/products/:id` | the full catalogue is already loaded |
| `GET /api/group-sessions/:code/participants` | a subset of the group state |
| `GET /api/group-sessions/:code/cart` | a subset of the group state |

Everything else in the API reference is wired up.

---

## Getting back into a group

The host is never a participant and a returning participant has already
joined, so `POST .../join` rejects both with a 409. "Open a group" therefore
reads the session with `GET /api/group-sessions/:code` first and only calls
join when the caller is genuinely new to it.

The join code is kept in `SharedPreferences`, so the home screen shows a button
with the code on it while the session is live. It is dropped as soon as the
order is placed, the code stops resolving, or the user taps Leave in the group
screen.

---

## Assumptions

- **Product images come from the backend's `image_urls`.** A given URL resolves
  only if the Cloudinary account holds an asset under that product's slug
  (`"Gulab Jamun (2 pc)"` → `gulab-jamun-2-pc`), so a partly-uploaded catalogue
  renders part photos and part icons. Each card falls back on its own, so a
  broken image never blanks the grid.
- **The group cart is keyed by product *and* member.** Each person's order for
  a dish is its own line, and you can only change your own. The menu's stepper
  shows your quantity, with a "group has N" note for the rest.
- **`added_by` is who added the item**, and stays put when somebody else
  changes the quantity. The app shows that person's display name in the group,
  not their username.
- **Being removed is not a ban.** The backend has no way to enforce one without
  auth, so a removed member can rejoin with the same code. The app says as much
  in the dialog rather than implying otherwise.
- **The host's log is host-only by query, not by auth.** An order is returned
  only to the user recorded as its host, so being a participant never gets you
  the host's view — but anyone holding a host's id can read that host's log.
- **"I have one" is not a login.** It matches a username against the user list
  and stores that id. There is no password because the backend has no concept
  of one; it exists so testing the group flow on two devices does not mean
  creating a fresh user each time.
- **Cart changes are optimistic.** The UI applies them immediately, rolls back
  if the server refuses, and then reconciles. A rejected add leaves no phantom
  line and consumes no stock.
- **No authentication, by design** — matching the backend. `POST /api/users`
  returns an id, the app stores it and sends it back on every request. There is
  no login, signup, password or token anywhere in the app.
- The stored user id is revalidated with `GET /api/users/:id` at startup. If the
  backend database was reseeded or dropped, the stale id is cleared and the
  create-user screen appears again instead of every later call failing.
- Usernames must be **at least 6 characters** — a backend rule, enforced in the
  form so the user gets an inline hint rather than a 400.
- Products have no images in the backend, so cards use a tinted initial-letter
  tile rather than an invented placeholder photo.
- The group menu refetches `/api/products` on each `group:state`, costing one
  extra GET per event, so stock stays live for products that are not yet in the
  shared cart.
- `cart[].qty` (units in the cart) and `cart[].product.qty` (stock still
  available) are different numbers and are never added together. An item in
  your cart stays editable even when its available stock has reached zero.
- The host's checkout button mirrors the backend's rules locally so a
  guaranteed-to-fail tap is not offered, but the **backend stays
  authoritative** — the button is driven by the state the server sent, and the
  server still re-checks on `POST .../order`.
- One order status only (`placed`), no payments and no pagination, because the
  backend has none of those.

---

## Testing

```bash
flutter analyze     # clean
flutter test        # 15 widget/unit tests, no backend needed
```

`test/widget_test.dart` covers first-run routing (create-user screen, not a
login), the 6-character username rule, the product card's ADD / stepper /
NO STOCK states, the cart-qty-vs-stock distinction, the host checkout gate,
`image_urls` parsing, and the nested `host` shape that the re-entry check and
the host's checkout button both depend on.

With the backend running, there is also a contract check that exercises every
endpoint and the socket for real:

```bash
cd ../inminutes_backend && npm run seed && npm start   # in one terminal
dart run --define=SERVER_URL=http://localhost:3000 tool/api_smoke.dart
```

It asserts 86 things, including that adding to a cart reserves stock, that
removing releases it, that `PATCH` quantity is absolute rather than a delta,
that a `group:state` broadcast arrives on a third connection when someone else
changes the cart, that a host and a returning participant both read as members
(so re-entry needs no join call), that a quantity change never steals
attribution, that removing a participant releases exactly the stock their lines
held and reaches a third socket as `group:participant_removed`, that the host's
log covers everyone including people who ordered nothing and sums to the order
total, that each 403/404/409 carries the message the UI shows, and that neither
duplicate-add message still mentions PATCH once the app has reworded it.

A fast double- or even triple-tap on the same ADD button was separately
verified by hand against a live backend: exactly one cart line at the correct
summed quantity every time, with the server agreeing — see `ShopState` in
[CLAUDE.md](CLAUDE.md#5-state-management) for what makes that true even
though the two network requests behind two taps can arrive at the server out
of order.

### Testing realtime by hand

Two devices (or an emulator plus Chrome) are the quickest way:

```bash
# Device A
flutter run --dart-define=SERVER_URL=http://192.168.x.x:3000
# Device B
flutter run -d chrome --dart-define=SERVER_URL=http://localhost:3000
```

Create a group on A, join it from B, then check that A adding an item appears
on B, B changing a quantity appears on A, and A removing an item turns B's copy
of that product's stock back to available — all without either side refreshing
or leaving the screen.

`Chocolate Brownie` (5), `Gulab Jamun (2 pc)` (3) and the two zero-stock items
in the seed data make the sold-out path easy to hit.

---

## Documentation

| File | Contents |
|---|---|
| [docs/FRONTEND.md](docs/FRONTEND.md) | The frontend explained in plain language — folders, screens, flows, realtime |
| [CLAUDE.md](CLAUDE.md) | Architecture decisions, the verified backend contract, and the rules for changing this code |
| [../inminutes_backend/apidocs.md](../inminutes_backend/apidocs.md) | Full REST and WebSocket reference |

---

## Deliberately left out

- Login / signup / passwords / tokens (the backend has no auth)
- A router package, DI container or code generation
- Product images, search, filtering and categories
- Payments, order tracking, pagination
- Animations beyond Flutter's built-in Material transitions
