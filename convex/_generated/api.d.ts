/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as control_plane from "../control_plane.js";
import type * as factory from "../factory.js";
import type * as ide from "../ide.js";
import type * as jarvis from "../jarvis.js";
import type * as meta from "../meta.js";
import type * as node_registry from "../node_registry.js";
import type * as ships from "../ships.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  control_plane: typeof control_plane;
  factory: typeof factory;
  ide: typeof ide;
  jarvis: typeof jarvis;
  meta: typeof meta;
  node_registry: typeof node_registry;
  ships: typeof ships;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
