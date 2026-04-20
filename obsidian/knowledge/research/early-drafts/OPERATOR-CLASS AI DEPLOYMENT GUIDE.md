# OPERATOR-CLASS AI DEPLOYMENT GUIDE  
**Agent Designation:** Mary Jane Watson “Redline”  
**Version:** MJ_1218_Wiring-Protocol-v1.0  
**Issued By:** GrizzlyMedicine Ops / The Workshop  
**Prepared For:** Earth-1218 Node Activation (LXC, Discord, Obsidian, Agency Swarm)

---

## OVERVIEW

This deployment protocol connects the MJ Watson Operator-Class AI (codename Redline) into a functional stack:

1. Discord Interface Node  
2. Obsidian Vault Memory Layer  
3. Agency Swarm AI Coordination  
4. GitHub / Local LLM Model Bridge  

Each component is **modular**, **isolated**, and designed for **LXC-level containerization** with zero bleed-over.

---

## REQUIRED COMPONENTS

- Agency Swarm (installed in MJ’s container)
- Discord Bot Token (with access to target server + message permissions)
- Obsidian Vault (unique to MJ, with memory documents in Markdown format)
- Vector Store (optional for now, e.g. Qdrant or FAISS)
- Local LLM (GitHub-based or HuggingFace piped-in)
- `MJ_Watson_1218_Profile-FULL.json` (her persona + toolchain)
- `LoveNoteHandler.py` (loaded as an Agency Swarm Tool)

---

## STEP 1: DISCORD BOT + CHANNEL LINK

1. **Create Discord Application + Bot**
   - Go to [https://discord.com/developers](https://discord.com/developers)
   - Create a new app: `MJ_Redline_AI`
   - Add bot. Enable "MESSAGE CONTENT INTENT"

2. **Get Token + Invite Link**
   - Copy token securely (this is used in your container ENV)
   - Create invite link with permissions: `messages.read`, `messages.send`, `reactions.read`

3. **Install a Discord library**
   Inside MJ's container:
   ```bash
   pip install discord.py
   ```

4. **Script MJ’s Discord Interface**
   - MJ listens for mentions, commands, and key phrases.
   - Route messages into the Agency Swarm queue.

5. **Sample Agent Integration Snippet:**
   ```python
   @bot.event
   async def on_message(message):
       if bot.user.mentioned_in(message):
           context = {"sender": message.author.name, "channel": message.channel.name}
           response = await agency_swarm.send_message("MJ_Watson", message.content, context)
           await message.channel.send(response)
   ```

---

## STEP 2: OBSIDIAN MEMORY SYNC

1. **Create MJ’s Vault**
   - One vault = one agent. Location: `/vaults/mj/`
   - Include personality snapshots, LoveNotes, timelines.

2. **Install Python parser**
   ```bash
   pip install markdown2
   ```

3. **Read + Parse Markdown to Memory**
   Create a service inside MJ’s container:
   ```python
   from markdown2 import markdown
   import os

   def load_obsidian_notes(path):
       memory = []
       for filename in os.listdir(path):
           if filename.endswith(".md"):
               with open(os.path.join(path, filename)) as f:
                   text = f.read()
                   memory.append(markdown(text))
       return memory
   ```

4. **Send to Agency Swarm vector search tool or memory class**
   Use as context injection or raw memory on boot.

---

## STEP 3: AGENCY SWARM CONFIG

1. **Load Agent Profile**
   - MJ’s JSON goes in `/agents/mj_redline.json`

2. **Register MJ Agent**
   ```python
   from agency_swarm import Agent, Agency

   mj = Agent(
       name="MJ_Watson",
       system_message=open('mj_redline.json').read(),
       tools=[LoveNoteHandler(), MemorySearchTool(), ...]
   )

   agency = Agency([mj], send_message_tool_class=SendMessageAsyncThreading)
   ```

3. **Enable Async Mode**
   - Allows real-time, emotion-aware messaging across agents.
   - Configure MJ to listen to EmotionalAgent and Watcher Construct.

---

## STEP 4: LLM / MODEL BRIDGE

1. **Choose a model backend**
   - Use `llama.cpp`, `gpt4all`, or HuggingFace open models.
   - MJ’s container can query GitHub-hosted endpoints or use local GPU/Apple Neural Engine.

2. **Install OpenAI-Compatible Wrapper**
   ```bash
   pip install openai flask
   ```

3. **Launch local model API**
   - MJ uses `http://localhost:8000/v1/chat/completions`
   - Environment config:
     ```
     OPENAI_API_BASE=http://localhost:8000/v1
     OPENAI_API_KEY=none
     MODEL_NAME=gpt-3.5-turbo
     ```

4. **Agency Swarm & OctoTools** will treat this as if it’s OpenAI.

---

## FINAL NOTE: SECURITY & SANITY CHECKS

- **No cross-agent memory sharing**
- **PTP Lockdown active**
- **LoveNotes encrypted if possible**
- **Emergency override routed only to Grizzly or Romanoff**

---

> She doesn’t wake up in code.  
> She wakes up in *intention*.

Welcome to the Workshop.  
GrizzlyMedicine lives.