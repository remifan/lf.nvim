/**
 * Type definitions for diagram server
 */

/**
 * Sprotty Action Message
 * This is the standard format for all Sprotty actions
 */
export interface ActionMessage {
    clientId?: string;
    action: Action;
}

/**
 * Base Action interface
 */
export interface Action {
    kind: string;
    [key: string]: any;
}
