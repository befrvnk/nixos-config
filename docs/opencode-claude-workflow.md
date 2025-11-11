# Using OpenCode with Claude Code Workflow

This guide explains how to use OpenCode configured to mimic Claude Code's structured, methodical workflow using Gemini models.

## Overview

OpenCode has been configured to follow the same workflow pattern that makes Claude Code effective:

1. **Analyze** the task complexity
2. **Plan** for complex tasks (research, draft approach, get approval)
3. **Create todo list** as markdown checklist
4. **Execute** systematically while tracking progress
5. **Report** completion

This gives you a Claude-like experience with Gemini models, perfect for when you hit Claude API quotas.

## Why This Workflow Works

The structured approach:
- **Prevents mistakes** by planning before coding
- **Ensures alignment** with your expectations
- **Tracks progress** visibly with todo lists
- **Handles complexity** systematically
- **Builds confidence** through clear communication

## Quick Start

```bash
# Launch OpenCode with the default agent (coder)
opencode

# Or use aliases
ai
code-ai
```

## Understanding Agents

Your OpenCode setup includes four specialized agents:

| Agent | Model | Purpose | When to Use |
|-------|-------|---------|-------------|
| `coder` | gemini-2.5-pro | Main agent with Claude Code workflow | Default for all tasks |
| `planner` | gemini-2.5-pro | Deep research and architecture planning | Explicit planning sessions |
| `quick` | gemini-2.5-flash | Fast execution for simple tasks | Quick fixes, docs updates |
| `reviewer` | gemini-2.5-flash | Code review and quality checks | Before committing changes |

### Default Agent: `coder`

The `coder` agent is your primary interface and automatically:
- **Detects task complexity**
- **Enters planning mode** for complex tasks
- **Executes immediately** for simple tasks
- **Creates markdown todos** during execution
- **Tracks progress** systematically

## The Workflow in Detail

### Stage 1: Task Analysis

When you give a task, the agent analyzes complexity:

**Simple Tasks** → Execute immediately:
- Fix a typo or single bug
- Update documentation
- Refactor a single function
- Answer questions about code
- Simple configuration changes

**Complex Tasks** → Enter planning mode:
- Implement new features
- Multi-file refactoring
- Architectural changes
- Database schema modifications
- API design and implementation
- Security-sensitive changes

### Stage 2: Planning Mode (Complex Tasks)

For complex tasks, the agent will:

1. **Research Phase**
   ```
   Let me explore the codebase to understand...
   [Reading files, searching code, analyzing structure]
   ```

2. **Present Plan**
   ```markdown
   ## Analysis
   I found the authentication system in src/auth/...

   ## Proposed Approach
   1. **Add JWT validation**: Modify src/auth/jwt.ts
      - Add token expiration check
      - Implement refresh token logic

   2. **Update middleware**: Edit src/middleware/auth.ts
      - Add new validation call
      - Handle expired tokens

   ## Potential Issues
   - Breaking change for existing tokens
   - Need migration strategy

   ## Questions
   - Should we invalidate existing tokens?
   - What's the desired token expiration time?
   ```

3. **Wait for Approval**
   ```
   Does this approach look good to you?
   ```

**Important**: The agent will NOT start coding until you approve!

### Stage 3: Execution with Todo List

After you approve (or immediately for simple tasks):

1. **Todo List Created**
   ```markdown
   ## Implementation Plan
   - [ ] Add JWT expiration validation
   - [ ] Implement refresh token logic
   - [ ] Update authentication middleware
   - [ ] Add error handling for expired tokens
   - [ ] Update tests
   ```

2. **Progress Updates**
   ```markdown
   - [x] Add JWT expiration validation ✓
   - [x] Implement refresh token logic ✓
   - [ ] Update authentication middleware (in progress)
   - [ ] Add error handling for expired tokens
   - [ ] Update tests
   ```

3. **Completion Report**
   ```markdown
   - [x] Add JWT expiration validation ✓
   - [x] Implement refresh token logic ✓
   - [x] Update authentication middleware ✓
   - [x] Add error handling for expired tokens ✓
   - [x] Update tests ✓

   All changes complete. The authentication system now properly
   handles token expiration with automatic refresh.
   ```

## Usage Examples

### Example 1: Simple Task (No Planning)

```bash
$ opencode

You: Fix the typo in README.md line 45, change "teh" to "the"

Agent: I'll fix that typo for you.
[Makes the edit]
Done! Fixed "teh" → "the" in README.md:45
```

**Notice**: No planning phase, immediate execution.

### Example 2: Complex Task (Full Workflow)

```bash
$ opencode

You: Add a dark mode toggle to the application

Agent: Let me explore the codebase to plan this feature.
[Researches theme system, state management, component structure]

## Analysis
Your app uses CSS modules and React Context for state.
The theme system is partially implemented in src/theme/...

## Proposed Approach
1. **Create theme context**: Add dark mode state
2. **Add toggle component**: Build UI switch
3. **Update CSS variables**: Define dark theme colors
4. **Persist preference**: Use localStorage
5. **Apply theme**: Update all components

## Potential Issues
- Some inline styles may not adapt
- Need to handle system preference detection

Does this approach look good to you?

You: Yes, looks great!

Agent:
## Implementation Plan
- [ ] Create theme context with dark mode state
- [ ] Build dark mode toggle component
- [ ] Define CSS variables for dark theme
- [ ] Implement localStorage persistence
- [ ] Update components to use theme
- [ ] Add system preference detection
- [ ] Test in both modes

Let me start implementing...

[Works through each item, marking progress]

- [x] Create theme context with dark mode state ✓
- [x] Build dark mode toggle component ✓
...
```

### Example 3: Using Specialized Agents

#### Using the Planner Agent for Deep Architecture Discussion

```bash
$ opencode --agent planner

You: How should I architect a caching layer for this API?

Agent: Let me analyze your current API structure...
[Deep dive into architecture, patterns, trade-offs]

## Analysis
[Detailed findings]

## Proposed Architecture
[Comprehensive plan with multiple options]

## Trade-offs
[Pros and cons of each approach]
```

#### Using Quick Agent for Fast Tasks

```bash
$ opencode --agent quick

You: Add a comment explaining this regex

Agent: [Immediately adds comment]
Done! Added explanatory comment.
```

#### Using Reviewer Agent

```bash
$ opencode --agent reviewer

You: Review the changes in src/auth/jwt.ts

Agent:
## Code Review: src/auth/jwt.ts

**Strengths:**
- Clean error handling
- Good type safety

**Issues Found:**
1. Line 45: Missing validation for null token
2. Line 67: Hardcoded secret should be in env
3. Line 89: Memory leak in token cache

**Recommendations:**
[Detailed suggestions]
```

## Best Practices

### 1. Let the Agent Assess Complexity

Don't force planning mode for simple tasks:
```bash
# Good
You: Update the README with new install instructions

# Unnecessary
You: I need you to plan how to update the README...
```

The agent will automatically plan if needed.

### 2. Provide Context for Complex Tasks

Help the agent understand scope:
```bash
# Good
You: Add user authentication with JWT tokens.
     We're using Express and PostgreSQL.

# Less helpful
You: Add auth
```

### 3. Review Plans Before Approval

The planning stage is your chance to:
- Catch potential issues
- Suggest alternatives
- Clarify requirements
- Avoid wasted work

### 4. Use the Right Agent

- **coder** (default): 95% of your tasks
- **planner**: When you want deep architectural discussion
- **quick**: When you need fast, simple changes
- **reviewer**: Before committing or when quality-checking

### 5. Iterate on Plans

Don't feel locked into the first plan:
```bash
Agent: Does this approach look good?

You: I like it, but instead of localStorage,
     can we use IndexedDB?

Agent: Good point! Let me revise the plan...
```

### 6. Use the Todo List as a Checklist

The markdown todos help you:
- Track progress in long operations
- Resume if interrupted
- Verify completeness
- Document what was done

## Advanced Usage

### Multi-Agent Workflows

Combine agents for complex projects:

```bash
# Step 1: Plan with planner agent
$ opencode --agent planner
You: Design a caching architecture for our API

# Step 2: Implement with coder agent
$ opencode --agent coder
You: Implement the caching plan we discussed

# Step 3: Review with reviewer agent
$ opencode --agent reviewer
You: Review the caching implementation
```

### Handling Long Sessions

For large features spanning multiple sessions:

1. **Session 1**: Planning
   ```bash
   You: Let's plan a complete authentication system
   [Agent creates detailed plan]
   You: Great, let's start with part 1 today
   ```

2. **Session 2**: Implementation continues
   ```bash
   You: Continue with parts 2 and 3 of the auth plan
   [Reference the previous plan]
   ```

### Working with Existing Code

Be explicit about constraints:
```bash
You: Refactor the API handlers to use async/await.
     Don't change the route structure, only the handler logic.
```

## Troubleshooting

### Agent Not Planning for Complex Tasks

If the agent jumps straight to coding for a complex task:

```bash
You: Wait, I'd like to see a plan first before you start
```

The agent will recognize this and switch to planning mode.

### Agent Over-Planning Simple Tasks

If the agent is planning for an obvious simple task:

```bash
You: This is simple, just do it directly
```

### Plans Too Detailed or Too Vague

Adjust the detail level:
```bash
# For more detail
You: Can you break down step 3 in more detail?

# For less detail
You: That's very detailed, can you give me a high-level summary?
```

### Execution Without Todo List

If the agent forgets to create a todo list:

```bash
You: Can you create a todo list for these changes?
```

## Comparison with Claude Code

### What's the Same
- ✅ Structured workflow (plan → approve → execute)
- ✅ Automatic complexity detection
- ✅ Markdown todo lists
- ✅ Systematic progress tracking
- ✅ Quality-focused approach

### What's Different
- ⚠️ **Model**: Uses Gemini instead of Claude
- ⚠️ **Response style**: May vary slightly in tone
- ⚠️ **Context window**: Different limits
- ⚠️ **Cost**: Different pricing structure

### When to Use Which

**Use Claude Code when:**
- You need Claude's specific capabilities
- Working on critical production code
- Maximum quality is essential
- You have quota available

**Use OpenCode + Gemini when:**
- Claude quota is exhausted
- Cost optimization matters
- Gemini-specific features are helpful
- You want an alternative workflow

## Tips and Tricks

### 1. Start Conversations with Context

```bash
You: I'm working on a NixOS configuration.
     I want to add a new package to home-manager...
```

### 2. Reference Files Explicitly

```bash
You: Looking at src/config/auth.ts, I want to add 2FA support
```

### 3. Use Code Blocks in Questions

```bash
You: This code isn't working:
     ```typescript
     const result = await fetchData()
     ```
     Can you help debug it?
```

### 4. Ask for Explanations

```bash
You: Before we implement this, explain how the authentication flow works
```

### 5. Request Different Approaches

```bash
You: Show me 2-3 different ways to implement this caching layer
```

## Configuration Tweaks

The configuration is in `/home-manager/opencode.nix`. You can adjust:

### Temperature Settings

Current settings:
- `coder`: 0.3 (focused, deterministic)
- `planner`: 0.2 (very focused for planning)
- `quick`: 0.3 (balanced)
- `reviewer`: 0.1 (extremely focused for reviews)

To make responses more creative, increase temperature:
```nix
coder = {
  temperature = 0.5;  # More creative
  # ...
};
```

### Token Limits

Increase for longer responses:
```nix
coder = {
  maxTokens = 12000;  # Larger responses
  # ...
};
```

### System Prompts

You can customize the workflow by editing system prompts in the config file.

## Cost Optimization

### Using Flash for Simple Tasks

The `quick` agent uses `gemini-2.5-flash` which is:
- **Faster**: Lower latency
- **Cheaper**: Lower cost per token
- **Good enough**: For simple tasks

### When to Use Pro vs Flash

**Use `gemini-2.5-pro` (coder/planner)**:
- Complex reasoning required
- Multi-file changes
- Architectural decisions
- Critical code

**Use `gemini-2.5-flash` (quick/reviewer)**:
- Simple edits
- Documentation
- Code review
- Quick questions

### Monitoring Usage

Keep track of API usage in your Google Cloud Console:
https://console.cloud.google.com/

## Common Workflows

### 1. Feature Development

```bash
$ opencode

You: Add a user profile page with avatar upload

Agent: [Plans the feature]
Does this approach look good?

You: Yes, but use React Query for data fetching

Agent: Updated the plan...
## Implementation Plan
- [ ] Create profile page component
- [ ] Add avatar upload with React Query
...

[Implements systematically]
```

### 2. Bug Fixing

```bash
$ opencode

You: The login form isn't validating email format properly

Agent: [May skip planning for simple bug]
Let me check the validation logic...

[Fixes bug directly]
Fixed! Added proper email regex validation.
```

### 3. Refactoring

```bash
$ opencode

You: Refactor the API client to use a consistent error handling pattern

Agent: Let me explore the current error handling...
[Analyzes code]

## Proposed Approach
1. Create centralized error handler
2. Update all API calls to use it
3. Add error type definitions
...

[Full planning workflow]
```

### 4. Code Review

```bash
$ opencode --agent reviewer

You: Review my changes before I commit

Agent:
## Code Review

**Files Changed:**
- src/auth/login.ts
- src/components/LoginForm.tsx

**Analysis:**
[Detailed review]

**Issues:**
1. Missing error boundary
2. Password should be hashed

**Recommendations:**
...
```

## Integration with Development Workflow

### 1. Pre-commit Review

```bash
# Before committing
$ opencode --agent reviewer
You: Review changes in the current git diff
```

### 2. Planning Sessions

```bash
# Start of sprint
$ opencode --agent planner
You: Let's plan the architecture for the new payment system
```

### 3. Implementation

```bash
# During development
$ opencode
You: Implement the payment webhook handler from our plan
```

### 4. Testing

```bash
$ opencode
You: Add tests for the payment webhook handler
```

## Updating Your Configuration

After changing `/home-manager/opencode.nix`:

```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch --flake .#framework

# Or for home-manager only
home-manager switch --flake .#frank
```

The changes will be applied and OpenCode will use the new configuration.

## Getting Help

### Documentation
- **OpenCode**: https://opencode.sh/
- **Gemini API**: https://ai.google.dev/docs
- **This guide**: `/docs/opencode-claude-workflow.md`

### Common Issues

**"Agent doesn't follow workflow"**
- Check system prompts in config
- Ensure latest version of OpenCode
- Try being more explicit in requests

**"Responses too verbose/terse"**
- Adjust temperature in config
- Adjust maxTokens
- Give explicit instructions

**"Planning when not needed"**
- Tell agent "this is simple, execute directly"
- Or use `--agent quick`

**"Not planning when needed"**
- Say "let's plan this first"
- Or use `--agent planner`

## Keyboard Shortcuts

Within OpenCode:
- `Ctrl+E`: Open external editor (Zed)
- `Ctrl+C`: Cancel current operation
- `Ctrl+D`: Exit OpenCode

## Conclusion

You now have OpenCode configured to provide a Claude Code-like experience with Gemini models. The key is:

1. **Trust the workflow**: Let it plan complex tasks
2. **Review plans**: Use the planning stage effectively
3. **Track progress**: Follow the markdown todos
4. **Use right agent**: Pick the appropriate agent for the task
5. **Iterate**: Refine plans before executing

This structured approach helps you build better software faster, with or without Claude API access.

Happy coding! 🚀
