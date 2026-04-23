// ============================================================
//  Edume Learning — Upload Helper
//  Supabase Storage upload with real-time progress tracking
// ============================================================

/**
 * Upload a file to Supabase Storage with progress callback.
 * Uses XMLHttpRequest so progress events fire correctly.
 *
 * @param {string}   bucket     - Storage bucket name
 * @param {string}   path       - File path within bucket
 * @param {File}     file       - File object to upload
 * @param {function} onProgress - Called with pct (0-100)
 * @returns {string} Public URL of uploaded file
 */
async function uploadWithProgress(bucket, path, file, onProgress = () => {}) {
  // 1. Get a signed upload URL from Supabase
  const { data: { signedUrl, token }, error } = await edumeDB.sb.storage
    .from(bucket)
    .createSignedUploadUrl(path);

  if (error) throw new Error('Failed to get upload URL: ' + error.message);

  // 2. Upload via XHR for progress events
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', signedUrl);
    xhr.setRequestHeader('Content-Type', file.type || 'application/octet-stream');

    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        onProgress(pct);
      }
    });

    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        // Build public URL
        const { data: { publicUrl } } = edumeDB.sb.storage
          .from(bucket)
          .getPublicUrl(path);
        resolve(publicUrl);
      } else {
        reject(new Error(`Upload failed with status ${xhr.status}`));
      }
    });

    xhr.addEventListener('error', () => reject(new Error('Network error during upload')));
    xhr.addEventListener('abort', () => reject(new Error('Upload aborted')));
    xhr.send(file);
  });
}

/**
 * Generate a short-lived signed URL for a private file (for video streaming).
 *
 * @param {string} bucket       - e.g. 'course-videos'
 * @param {string} storagePath  - Path within bucket
 * @param {number} expiresIn    - Seconds until expiry (default 3600 = 1hr)
 * @returns {string} Signed URL
 */
async function getSignedUrl(bucket, storagePath, expiresIn = 3600) {
  const { data, error } = await edumeDB.sb.storage
    .from(bucket)
    .createSignedUrl(storagePath, expiresIn);
  if (error) throw new Error(error.message);
  return data.signedUrl;
}

/**
 * Delete a file from storage.
 */
async function deleteStorageFile(bucket, path) {
  const { error } = await edumeDB.sb.storage.from(bucket).remove([path]);
  if (error) throw new Error(error.message);
}

/**
 * Extract the bucket name and path from a full Supabase storage URL.
 * Useful when you only have the public URL and need to generate a signed URL.
 */
function parseStorageUrl(url) {
  const match = url.match(/\/storage\/v1\/object\/(?:public|sign)\/([^/]+)\/(.+?)(\?|$)/);
  if (!match) return null;
  return { bucket: match[1], path: match[2] };
}
