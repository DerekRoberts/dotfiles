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
- **Explicit Typing:** Explicitly declare types on all function parameters, return signatures, and exported interfaces. Ban implicit `any`; never bypass strict typing.
- **Null & Relations:** Use `?.` or explicit early return guards before dereferencing unvalidated relations or nullable objects.
