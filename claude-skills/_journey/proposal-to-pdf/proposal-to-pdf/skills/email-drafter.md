# Skill: email-drafter

Draft the short warm cover email that accompanies the proposal PDF.

## Inputs

- `prospect_name`: first name of the recipient
- `proposal_summary`: one-sentence summary of what the proposal recommends
- `author_name`: sender's first name
- `attachment_filename`: the PDF filename so the email can reference it naturally

## Output

A 3-to-5 sentence email, plain text, with a subject line. Ready to paste into a mail client with the PDF attached.

## Structure

1. **Subject** — specific, no "Checking in" or "Following up"
2. **Opening** — one sentence that references the call or thread, not "I hope this email finds you well"
3. **What's attached** — one sentence naming the attachment and the recommendation
4. **Soft next step** — one sentence proposing the next action (a 15-min call, a reply with questions, a go/no-go)
5. **Sign-off** — first name only

## Rules

- No "I hope this email finds you well"
- No "Please let me know if you have any questions"
- No "As per our conversation"
- No "Just following up"
- No "Please find attached" (reference the attachment naturally instead)
- Write like a peer, not a vendor
- 3-5 sentences total, not including subject and sign-off

## Template

```
Subject: {Specific subject — e.g. "Proposal: content engine build for {Company}"}

{Prospect first name} —

{One sentence anchoring the email to the prior conversation.} I put together a short proposal based on what you shared — it's attached as {attachment_filename}.

{One sentence on the recommendation — e.g. "Short version: start with the 4-week sprint, then decide on the retainer."}

{Soft next step — e.g. "Happy to jump on 15 minutes this week if it's easier to walk through live, or just reply with thoughts."}

{Author first name}
```

## Failure Modes

- **Unknown prospect name** → use the company name instead of a first name; never invent one
- **No prior conversation** → this is a cold intro, not a post-discovery proposal — use a different skill (cold-outreach), not this one
