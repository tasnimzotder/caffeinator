/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Launch Automatically - Launch Caffeinator in the background when it is not running */
  "launchAutomatically": boolean,
  /** Application Path - Path to Caffeinator.app. Change this when testing a development build. */
  "appPath": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `start-session` command */
  export type StartSession = ExtensionPreferences & {}
  /** Preferences accessible in the `toggle` command */
  export type Toggle = ExtensionPreferences & {}
  /** Preferences accessible in the `stop` command */
  export type Stop = ExtensionPreferences & {}
  /** Preferences accessible in the `status` command */
  export type Status = ExtensionPreferences & {}
  /** Preferences accessible in the `open-app` command */
  export type OpenApp = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `start-session` command */
  export type StartSession = {}
  /** Arguments passed to the `toggle` command */
  export type Toggle = {}
  /** Arguments passed to the `stop` command */
  export type Stop = {}
  /** Arguments passed to the `status` command */
  export type Status = {}
  /** Arguments passed to the `open-app` command */
  export type OpenApp = {}
}
