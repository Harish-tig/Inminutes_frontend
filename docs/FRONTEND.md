# The frontend, explained simply

This document walks through the Flutter app the way you would read it: what
each folder is for, what each screen does, how data gets in and out, and how
two phones stay in sync. No prior knowledge of the project is assumed.

If you want the short version: **the server owns the truth, the app just draws
it.** Everything below is a consequence of that one idea.

---

## 1. Folder structure

```
lib/
├── main.dart              starts the app, sets up shared state, picks the first screen
│
├── models/                plain Dart classes that mirror the backend's JSON
│   ├── app_user.dart      AppUser      — id + username
│   ├── product.dart       Product      — name, price, available stock
│   ├── cart_item.dart     CartItem     — a line of your own cart
│   │                      GroupCartItem — a line of the shared cart (+ who added it)
│   ├── participant.dart   Participant  — someone who joined a group
│   ├── group_session.dart GroupSession — the whole group screen in one object
│   └── order.dart         Order, OrderLine
│
├── services/              the only two files that talk to the outside world
│   ├── api_service.dart   every REST call, plus error handling
│   └── socket_service.dart  the Socket.IO connection
│
├── state/                 the app's memory, as three ChangeNotifiers
│   ├── user_state.dart    who you are
│   ├── shop_state.dart    the menu and your personal cart
│   └── group_state.dart   one live group session
│
├── screens/               one file per screen
├── widgets/               pieces used by more than one screen
└── utils/
    ├── config.dart        the backend URL — the only copy of it
    ├── app_theme.dart     colours, corner radius, spacing — the only copy of them
    └── ui.dart            showSnack / showErrorSnack / formatPrice
```

Two things are worth remembering:

- **Widgets never call `http` directly.** They call a method on a state object,
  which calls `ApiService`. So if you want to know every request the app can
  make, you only have to read one file.
- **There is no repository, no use-case class, no dependency injection.** The
  chain is short on purpose:

```
Widget  ->  state object  ->  ApiService  ->  backend
```

---

### Getting back into a group

The host is never a participant, and someone who already joined cannot join
twice — `POST .../join` rejects both with a 409. So "open a group" reads the
session first and only calls join when the caller is genuinely new to it. That
is what makes backing out of the group screen safe: the home screen keeps a
button with the join code on it, and tapping it walks straight back in.

The code lives in `SharedPreferences` and is dropped as soon as the session
closes, the code stops resolving, or the user taps Leave.

---

### Where the look comes from

All colours, radii and the three text styles that carry the design
(`sectionHeading`, `itemName`, `buttonLabel`) live in `lib/utils/app_theme.dart`.
Violet is the brand, lime is the accent and only ever sits on violet, and
anything out of stock turns grey. If you want to restyle the app, that is the
only file you need to open.

---

## 2. Screen flow

```
                      app starts
                          │
              is a user id already saved?
                    ┌─────┴─────┐
                   no           yes
                    │             │
             UserScreen           │
       (type a name, no login)    │
                    └─────┬───────┘
                          ▼
                     HomeScreen                ← the default: individual ordering
                          │
      ┌───────────────────┼───────────────────────────┐
      ▼                   ▼                           ▼
  CartScreen         OrdersScreen             GroupEntryScreen
  change qty,        past orders         "Create group" or "Join with a code"
  remove, order                                        │
                                                       ▼
                                                 GroupScreen              ← live
                                            participants, shared cart,
                                            Ready button / host checkout
                                                       │
                                                       ▼
                                              GroupMenuScreen
                                       the menu, but Add writes to the
                                              *shared* cart
```

Navigation is plain `Navigator.push` and `Navigator.pop`. There is no router
package, because there is nothing here a router would make easier.

### What each screen is responsible for

| Screen | Does |
|---|---|
| `user_screen.dart` | Two modes. **New user** creates one with `POST /api/users`. **I have one** looks an existing username up in `/api/users` and continues as them. Neither is a login — there is no password, and the backend has no auth. |
| `home_screen.dart` | The menu with live stock, a prominent **Group Order** button at the top, a badged cart icon in the app bar, and a cart summary bar at the bottom once it has something in it. Individual ordering is the default mode. |
| `cart_screen.dart` | Your personal cart: change quantity, remove a line, place the order. |
| `orders_screen.dart` | Order history — your own orders and group orders you were part of, with each group line showing who added it. |
| `group_orders_screen.dart` | Groups **you hosted**, each with the split of who owes what. Reached from the icon in My orders. |
| `group_entry_screen.dart` | Two choices: create a group (you become host) or join one with a code and a display name. |
| `group_screen.dart` | The live group session. Join code, participants and their Ready status, the shared cart, and either a Ready toggle (participant) or Place order (host). The host can also remove a member here. |
| `group_menu_screen.dart` | The same menu, but every Add / +/− writes to the shared group cart. |

---

## 3. How the app talks to the backend

Everything goes through `lib/services/api_service.dart`.

```dart
final products = await ApiService.getProducts();
await ApiService.addToCart(userId, productId, 1);
final state = await ApiService.setReady(joinCode, userId, true);
```

### The response shapes it has to deal with

The backend is *almost* consistent, and `ApiService` absorbs the exceptions so
nothing else has to know about them:

| Case | Body |
|---|---|
| Success, nearly always | `{"data": ...}` |
| `POST /api/users` | `{"id": "...", "name": "..."}` — no `data` wrapper |
| `POST /api/group-sessions` | `{"join_code": "..."}` — no `data` wrapper |
| Most errors | `{"mssg": "..."}` |
| `POST /api/users` errors | `{"error": "..."}` |
| Validation errors | `{"errors": [ ...list of issues... ]}` |

One private method, `_decode`, handles all six. Everywhere else in the app,
a call either returns a model or throws.

### When something goes wrong

`ApiService` throws `ApiException(statusCode, message)`, where `message` is
already safe to put in front of a person.

- If the backend sent wording, that wording is used. The backend's messages are
  already friendly — *"Insufficient stock"*, *"Host cannot join their own group
  as a participant"*, *"Display name already exists in this group"* — so
  rewriting them would only lose information. Two messages are the exception:
  *"...use PATCH to update quantity"* (personal and group cart, both for
  adding a duplicate line) reference the backend's own HTTP verb, so
  `ApiService` rewrites those two exact strings to plain English before a
  widget ever sees them.
- A `500` **always** shows "Something went wrong on the server.", never the
  backend's own text — that status is developer-facing by definition, so
  showing its body (`"Internal server error"`, `"Failed to fetch cart"`, …)
  would not help anyone.
- Otherwise a short line is derived from the status code: `403` → "You are not
  allowed to do that.", `404` → "Not found."
- No connection at all → "Cannot reach the server. Check your connection."

Screens catch it and show `e.message` in a `SnackBar`. A raw exception or stack
trace is never shown.

### The `qty` trap — read this one

There are **two different `qty` fields** and they mean opposite things:

| Field | Meaning |
|---|---|
| `cartItem.qty` | how many units are in the cart |
| `cartItem.product.qty` | how many units are **still available to reserve** |

The backend reserves stock the instant something enters a cart — not at
checkout. So a product you have 3 of in your cart can perfectly well report
`product.qty == 0`: that means *nobody can add any more*, not *your line is
invalid*. The UI reflects exactly that: the `+` button greys out, the line stays
editable, and only a product with zero stock **and** nothing in your cart shows
*Sold out*.

Never add the two numbers together.

---

### Why the group cart is grouped by person

The obvious design — one line per dish with a quantity — cannot answer "who
wanted this?". If two people order the same pizza, the second person's `POST`
is a duplicate, so they have to bump the first person's line, and the cart ends
up reading "4 pizzas, added by whoever was first". The information is gone.

So a line is identified by **dish plus person**. The screen renders one basket
per member with its own subtotal, the totals still add up to the order total,
and the menu's stepper edits your own quantity while a small note tells you what
the group has altogether.

---

### Why the cart feels instant

A cart change used to wait for the write and then two more reads before
anything on screen moved. Now `ShopState` changes its own copy first, notifies,
and only then sends the request — so the card redraws in the same frame you tap
it. If the server refuses (say the last one just went), the change is put back
and you get the message.

A counter makes that safe when you tap quickly: each change claims a number,
and a late reply is ignored if a newer change has already started. Otherwise
the first reply to arrive could quietly undo your last two taps.

Two more things had to be true for a real double-tap, not just a quick single
one, to behave correctly:

- **Tapping ADD twice must not create two lines.** `addToCart` checks whether
  the product is already in the cart and, if so, bumps that line through
  `updateCartQty` instead of sending a second `POST` — which the backend
  would reject as a duplicate anyway, with a message that talks about `PATCH`.
- **The two real network calls have to leave in the order the taps happened,**
  even though the local, on-screen state already updated in that order the
  moment each tap landed. Nothing about two independent HTTP requests
  guarantees they *arrive* at the server in the order they were sent — this
  was checked by hand, and a `PATCH` from a second tap did land before the
  first tap's `POST` had committed, 404ing on a line that was about to exist.
  `ShopState` now keeps one pending-request future per product and makes each
  new request for that product wait for the previous one to settle first. A
  different product is never held up by this.

---

## 4. State management

The app uses `provider` with `ChangeNotifier` — the simplest option that still
lets a single socket event refresh a list without redrawing the screen.

There are exactly three state objects:

```dart
UserState    // who you are; saved to SharedPreferences
ShopState    // the menu + your personal cart
GroupState   // one live group session + its socket
```

`UserState` and `ShopState` are created once in `main.dart` and live for the
whole app. **`GroupState` is different**: it is created by the route that opens
the group screen —

```dart
// GroupScreen.route(...)
ChangeNotifierProvider(
  create: (_) => GroupState(joinCode: joinCode, userId: userId, shop: shop),
  child: const GroupScreen(),
)
```

— so the socket connects when you open a group and is disposed when you leave
it. There is no app-wide connection to remember to clean up.

`GroupState` is handed `ShopState` so that when a group event arrives, it can
also refresh the menu. That is what makes someone else's reservation show up as
*Sold out* on your group menu without you touching anything.

### Why the scroll position never jumps

This matters when updates arrive while someone is scrolling, so it is built in
rather than left to care:

- Each screen is a `StatefulWidget` that **owns its `ScrollController`**. A
  socket event rebuilds the list's contents, not the screen, not the
  controller.
- Updates are consumed by `Consumer` / `Selector` wrapped around the smallest
  subtree that actually shows the changed data — the participants card, the
  cart list, the bottom bar.
- `ListView` children are rebuilt in place, so the offset is untouched.
- Nothing calls `pushReplacement` on the screen you are already on. "Refresh by
  navigating" is exactly the bug this design avoids.

---

## 5. Socket.IO flow

The backend runs Socket.IO 4. Socket.IO is a protocol *on top of* WebSocket, so
the app uses the `socket_io_client` package rather than Dart's raw `WebSocket`.

```
connect to  http://<server>        (no /api — that is REST only)
      │
      ├── emit "group:join"  <joinCode>      → the server puts you in that room
      │
      └── on  "group:state"  <full session>  → replace local state, redraw
```

All of that lives in `lib/services/socket_service.dart`, about 50 lines.

Three rules the code follows:

**1. The client never writes over the socket.**
Every change — joining, adding an item, changing a quantity, toggling ready,
placing the order — is a normal REST call. The socket only carries results
outward. That keeps validation in exactly one place: the server.

```
you tap "+"
   → PATCH /api/group-sessions/:code/cart/:productId
      → backend updates MongoDB
         → backend reads the fresh session
            → backend emits group:state to everyone in the room
```

**2. There is one event and it carries everything.**
`group:state` contains the whole session: join code, active flag, host,
participants with their ready flags, and every cart line with its product's
live stock. So the handler is one line —

```dart
_session = GroupSession.fromJson(json);
```

— and there is no diffing, no merging, and no risk of the screen drifting out
of sync with the database.

**2b. One event is not state.** `group:participant_removed` exists because a
kicked client cannot work out from the new state that it was removed — it would
just see itself missing from the list. If the id is yours, the app says so and
leaves the screen; if it is someone else's, it is ignored, because the
`group:state` that follows already has them gone.

**3. A reconnect fixes itself.**
`group:join` is re-emitted inside the `onConnect` callback, so if the network
drops and returns, the app re-subscribes on its own. The app bar shows *Live*
or *Connecting* straight from the socket's connection callbacks.

The device that made a change does not wait for its own broadcast: the REST
response already contains the same full state, so it applies that immediately
and the broadcast is simply redundant for that one device.

---

## 6. Normal (individual) order flow

```
HomeScreen        GET  /api/products                    ← live stock
    │  tap Add                        ↓ card updates this same frame
    ▼             POST /api/users/:id/cart              ← reserves stock now
CartScreen        (badged icon in the app bar, and the bottom bar once
 ← always            the cart has something in it, both open this screen)
    │  +/-                            ↓ card updates this same frame
    ▼             PATCH /api/users/:id/cart/:productId  ← absolute qty, not a delta
    │  remove                         ↓ card updates this same frame
    ▼             DELETE /api/users/:id/cart/:productId ← releases the stock
    │  Place order
    ▼             POST /api/users/:id/orders            ← no body; built from the cart
Order placed dialog → back to the menu
```

Three details worth knowing:

- **`PATCH` takes the new total, not a change.** Going from 2 to 5 sends
  `{"qty": 5}` and the backend reserves 3 more by itself. To remove a line, use
  `DELETE` — `qty: 0` is rejected by validation.
- **The card updates before the network call finishes, not after.** `POST`,
  `PATCH` and `DELETE` return the cart with the product as a bare id, so they
  cannot be used to redraw the card by themselves — but the card does not wait
  for them anyway. See "Why the cart feels instant" above: `ShopState` applies
  the change locally first, and only re-reads the cart and products afterward
  to reconcile with whatever the server actually ended up with.
- **The cart is reachable from two places on the home screen**: a badged cart
  icon at the top of the app bar (always there, showing the item count), and a
  summary bar pinned to the bottom once the cart has anything in it.

---

## 7. Group order flow

```
Host                                          Participant
────                                          ───────────
Group Order → Create group
POST /api/group-sessions
    → join code "IB3F4F8J"
         │
         │  shares the code                   Group Order → Open a group
         │                                    GET  .../group-sessions/:code
         │                                      already a member? ─ yes ─► go in
         └───────────────────────────────────► POST .../join {userId, display_name}
                                                       │
         ◄───── group:state ────────────────────────────┘

Both can add to the shared cart:
    POST   .../cart            {userId, productId, qty}
    PATCH  .../cart/:productId {userId, qty}
    DELETE .../cart/:productId?userId=...      ← id in the query string here

         ◄───── group:state after every one of those ──►

                                              Taps "I'm ready"
                                              PATCH .../participants/:userId/ready
         ◄───── group:state ────────────────────────────┘

"Place order" enables only once the
state the server sent says everyone
is ready

POST .../order {userId}
    → order created, session closed
         ───── group:state (active: false) ──►
```

Rules the UI follows, all of them the backend's:

- **The host is never a participant** and therefore has no Ready flag. The host
  appears in the list with a *Host* badge instead. "Everyone is ready" refers
  only to the people who joined.
- **Only members can change the shared cart** — the host or someone who joined.
- **Only the host can check out**, and only with at least one participant, a
  non-empty cart, and everyone ready.
- **The shared cart holds one line per product per person.** If Bob orders two
  pizzas and you order two more, that is two lines of two — not one line of
  four. Adding a dish *you* already added is rejected (use the stepper); adding
  one somebody else added is fine and creates your own line.
- **You can only change your own lines.** The backend returns `404` otherwise,
  so other people's rows are shown read-only rather than offering a control
  that would fail.
- **`added_by` records who added the line** and never moves.
- **Names come from the session, not the account.** The backend fills
  `added_by` with the username; the app resolves it to the display name that
  person uses in this group, so the shared cart and the participant list agree.
- **Once the order is placed the session is closed.** The app greys out the
  controls and shows "This session is closed" — on every device at once,
  because the final `group:state` says `active: false`.

The host's button is disabled with the reason spelled out underneath — "Waiting
for Carol to be ready.", "Add something to the shared cart first." — computed
from the session the server sent. The server still re-checks everything when the
button is finally tapped; the local check exists only so a guaranteed failure is
not offered as a tap.

---

## 8. Realtime synchronization, concretely

What the assignment asks for, and where it comes from:

| What happens | What the other device sees | Why |
|---|---|---|
| A adds the last Burger | B's Burger turns *Sold out* | the backend reserves stock on add; the new `product.qty` of `0` rides along in `group:state`, and the group menu also refetches `/api/products` |
| A removes the Burger | B's Burger becomes available again | removal releases the reservation, and the same event carries the restored stock |
| A changes a quantity 1 → 2 | B's line reads 2 | the cart line in `group:state` has the new `qty` |
| A joins | B's participant list grows | `group:state` after the join |
| A marks ready | B's list shows *Ready*, and the host's button may enable | `group:state` after the ready toggle |
| The host places the order | everyone's session shows closed | final `group:state` with `active: false` |

In every row, **nobody refreshes, and nobody navigates away and back**. The
existing state object is updated from the event and only the affected part of
the screen redraws.

---

## 9. Important assumptions

1. **There is no authentication, and that is intentional** — the backend has
   none. Creating a user returns an id; the app stores it and sends it back.
   Anyone who knows an id can act as that user. Adding real auth later means
   taking `userId` from a verified token instead of the request body; nothing
   else in this app would change.

2. **The saved user id is checked at startup.** If the backend database was
   reseeded, `GET /api/users/:id` returns 404, the stored id is cleared, and the
   create-user screen appears again — rather than every later call failing for
   no visible reason. If the server is merely unreachable, the cached user is
   kept and the app carries on.

3. **Usernames must be at least 6 characters.** That is a backend rule; the form
   checks it locally only so you get an inline hint instead of a 400.

4. **Products have no images** in the backend, so cards show a tinted
   initial-letter tile rather than an invented placeholder photo.

5. **The group menu refetches the product list on every group event.** That is
   one extra GET per event, accepted because it is what keeps stock honest for
   products that are not yet in the shared cart.

6. **The backend is authoritative, always.** Local checks exist only to avoid
   offering an action that is certain to fail. Nothing in the app assumes a
   change succeeded before the server said so.

7. **One order status (`placed`), no payments, no pagination** — the backend has
   none of them, so the app invents none.
