// Obfuscation utilities for protecting sensitive code and data
// These utilities help protect WASM loading, decryption keys and functions

// XOR key - this adds another small layer of protection
const KEY = [0x5a, 0xf1, 0x9e, 0x3d, 0x24, 0xb7, 0x6c];

/**
 * Encodes a string to obfuscate it in the source code
 * DO NOT modify this encoding algorithm without updating the decode function
 */
export function encode(str: string): string {
  const encoded = [];
  for (let i = 0; i < str.length; i++) {
    const charCode = str.charCodeAt(i);
    const keyChar = KEY[i % KEY.length];
    encoded.push(String.fromCharCode(charCode ^ keyChar));
  }

  // Convert to base64 for better text safety
  return btoa(encoded.join(''));
}

/**
 * Decodes a previously encoded string
 */
export function decode(encoded: string): string {
  try {
    const str = atob(encoded);
    const decoded = [];

    for (let i = 0; i < str.length; i++) {
      const charCode = str.charCodeAt(i);
      const keyChar = KEY[i % KEY.length];
      decoded.push(String.fromCharCode(charCode ^ keyChar));
    }

    return decoded.join('');
  } catch (e) {
    // Fallback in case of decoding errors
    console.error('Failed to decode string:', e);
    return '';
  }
}

/**
 * Decrypt a WASM binary
 * This is a placeholder implementation - replace with your actual decryption logic
 */
function decryptWasmBinary(encryptedBuffer: ArrayBuffer, key: Uint8Array): ArrayBuffer {
  // Create a view of the encrypted buffer
  const encryptedView = new Uint8Array(encryptedBuffer);
  const decrypted = new Uint8Array(encryptedBuffer.byteLength);

  // Simple XOR decryption - replace with stronger algorithm in production
  for (let i = 0; i < encryptedView.length; i++) {
    decrypted[i] = encryptedView[i] ^ key[i % key.length];
  }

  return decrypted.buffer;
}

/**
 * Creates a function from encoded string
 * This allows obfuscating function code and only constructing it at runtime
 *
 * @param encodedFn - The encoded function string (encode(functionString))
 * @returns The decoded and constructed function
 */
export function createFunction<T extends (...args: any[]) => any>(encodedFn: string): T {
  try {
    // Decode the function string
    const fnStr = decode(encodedFn);

    // Create the function dynamically
    // eslint-disable-next-line no-new-func
    return new Function(`return ${fnStr}`)() as T;
  } catch (e) {
    console.error('Failed to create function from encoded string:', e);
    return (() => null) as unknown as T;
  }
}

/**
 * Loads and decrypts a WASM module from an encoded URL
 *
 * @param encodedUrl - The encoded URL to the WASM file
 * @param decryptionKey - Key to decrypt the WASM binary (if encrypted)
 * @returns A promise resolving to the instantiated WebAssembly instance
 */
export async function loadWasmModule(
  encodedUrl: string,
  decryptionKey?: Uint8Array,
): Promise<WebAssembly.WebAssemblyInstantiatedSource> {
  const url = decode(encodedUrl);

  // Fetch the WASM module
  const response = await fetch(url);
  let buffer = await response.arrayBuffer();

  // Decrypt the WASM binary if a key is provided
  if (decryptionKey) {
    buffer = decryptWasmBinary(buffer, decryptionKey);
  }

  // Compile and instantiate the WASM module
  return WebAssembly.instantiate(buffer);
}
