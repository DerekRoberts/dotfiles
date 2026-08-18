---
name: typescript-standards
description: Enforce TypeScript strict mode, definite assignment, explicit typing, and null safety rules. Trigger when inspecting, modifying, or creating .ts or .tsx files.
---

# TypeScript & Strict Mode Standards

## Use When
- Modifying, inspecting, or creating `.ts` or `.tsx` files.
- Configuring TypeScript compiler options (`tsconfig.json`).
- Writing or refactoring NestJS, TypeORM, or React/Vue TypeScript code.

## Standards

- **Strict Checks:** Enforce `"strict": true` and `"noImplicitAny": true` in `api/` and `libs/` workspaces. Never downgrade strict flags or use `// @ts-ignore` / `// @ts-nocheck`.
- **Definite Assignment:** NestJS/TypeORM decorator-initialized properties use `!`, not optional `?`.
- **Explicit Typing:** No implicit `any` where inference isn't safe.
- **Null & Relations:** Use `?.` or early returns unless loaded/validated.
