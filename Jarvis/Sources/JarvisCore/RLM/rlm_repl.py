#!/usr/bin/env python3
import argparse
import code
import json
import pathlib
import re


class PromptEnvironment:
    def __init__(self, prompt: str):
        self.P = prompt
        self.symbols = self._symbolize(prompt)

    def _symbolize(self, prompt: str):
        paragraphs = [segment.strip() for segment in re.split(r"\n\s*\n", prompt) if segment.strip()]
        if not paragraphs:
            paragraphs = [prompt.strip()] if prompt.strip() else [""]
        return {f"P{index}": value for index, value in enumerate(paragraphs)}

    def _score(self, text: str, query: str) -> int:
        query_tokens = set(re.findall(r"[A-Za-z0-9_]+", query.lower()))
        text_tokens = re.findall(r"[A-Za-z0-9_]+", text.lower())
        overlap = sum(1 for token in text_tokens if token in query_tokens)
        density = len(text_tokens) // max(1, len(query_tokens) or 1)
        return overlap * 10 - density

    def recursive_query(self, query: str, depth: int = 0):
        ranked = sorted(
            self.symbols.items(),
            key=lambda item: self._score(item[1], query),
            reverse=True,
        )
        ranked = ranked[:3]

        trace = [f"depth={depth}: ranked {name} score={self._score(text, query)}" for name, text in ranked]
        top_matches = [{"symbol": name, "text": text, "score": self._score(text, query)} for name, text in ranked]

        if depth >= 2:
            return {
                "response": " ".join(match["text"] for match in top_matches).strip(),
                "symbols": list(self.symbols.keys()),
                "trace": trace,
                "topMatches": top_matches,
            }

        refined_matches = []
        for match in top_matches:
            sentences = [sentence.strip() for sentence in re.split(r"(?<=[.!?])\s+", match["text"]) if sentence.strip()]
            if len(sentences) <= 1:
                refined_matches.append(match)
                continue
            child = PromptEnvironment("\n".join(sentences))
            child_result = child.recursive_query(query, depth + 1)
            trace.extend(child_result["trace"])
            best_text = child_result["response"] or match["text"]
            refined_matches.append({"symbol": match["symbol"], "text": best_text, "score": match["score"]})

        response = " ".join(item["text"] for item in refined_matches).strip()
        return {
            "response": response,
            "symbols": list(self.symbols.keys()),
            "trace": trace,
            "topMatches": refined_matches,
        }


def propose_grid(grid_json: str) -> list:
    """Return the input grid unchanged — identity stub, pure stdlib.

    The RLM subprocess is local (PRINCIPLES §2). This stub satisfies the
    smoke-test contract; a real inference backend can replace it without
    changing the Swift bridge API.
    """
    grid = json.loads(grid_json)
    return grid


def start_repl(prompt: str):
    env = PromptEnvironment(prompt)

    def query_prompt(question: str):
        return env.recursive_query(question)

    banner = (
        "Jarvis RLM REPL\n"
        "Loaded prompt as symbolic variable P.\n"
        "Use env.symbols to inspect segments and query_prompt('your question') to recurse."
    )
    code.interact(banner=banner, local={"P": env.P, "env": env, "query_prompt": query_prompt})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["query", "repl", "propose_grid"], required=True)
    parser.add_argument("--prompt-file", default="")
    parser.add_argument("--query", default="Summarize the prompt.")
    parser.add_argument("--grid-json", default="[]")
    args = parser.parse_args()

    if args.mode == "propose_grid":
        result = propose_grid(args.grid_json)
        print(json.dumps(result))
        return

    prompt = pathlib.Path(args.prompt_file).read_text(encoding="utf-8")
    if args.mode == "repl":
        start_repl(prompt)
        return

    env = PromptEnvironment(prompt)
    print(json.dumps(env.recursive_query(args.query)))


if __name__ == "__main__":
    main()
