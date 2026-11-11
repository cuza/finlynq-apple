# Log Apple Pay purchases in Finlynq

This shortcut adds each Apple Pay purchase to Finlynq automatically. You set it up once on your iPhone.

## 1. Install Finlynq

Install Finlynq on your iPhone and sign in once.

## 2. Add the shortcut

1. Open `Log Apple Pay purchase.shortcut` on your iPhone. You can AirDrop it, or tap it in Messages, Mail or Files.
2. The Shortcuts app opens. Tap Add Shortcut.

## 3. Create the Wallet automation

iOS doesn't let an app create this part, so you make it yourself in the Shortcuts app.

1. Open Shortcuts and tap the Automation tab.
2. Tap the + button (or New Automation if you have none yet).
3. Scroll down and tap Transaction.
4. Under Cards, pick the cards you pay with. Leave Categories and Merchants as they are.
5. Choose Run Immediately, then tap Next.
6. Under My Shortcuts, tap Log Apple Pay purchase.
7. If you see a Run Shortcut action instead, tap its input field and choose Shortcut Input. Then tap Done.

## What happens on each purchase

When you pay with one of those cards, the automation sends the merchant, the amount and the card name to Finlynq. Finlynq adds the purchase as a transaction with the note "Apple Pay". You don't need to open the app.

If Finlynq can't send it right away, for example with no signal, it keeps the purchase and sends it next time you open the app. The first time a card is used, Finlynq may ask you to pick which account it belongs to.
