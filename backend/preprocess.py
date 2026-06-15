import cv2
import numpy as np
import os

def _order_points(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect

def _four_point_transform(image, pts):
    rect = _order_points(pts)
    (tl, tr, br, bl) = rect

    width_a = np.linalg.norm(br - bl)
    width_b = np.linalg.norm(tr - tl)
    max_width = max(int(width_a), int(width_b))

    height_a = np.linalg.norm(tr - br)
    height_b = np.linalg.norm(tl - bl)
    max_height = max(int(height_a), int(height_b))

    if max_width < 100 or max_height < 100:
        return image

    dst = np.array(
        [
            [0, 0],
            [max_width - 1, 0],
            [max_width - 1, max_height - 1],
            [0, max_height - 1],
        ],
        dtype="float32",
    )
    m = cv2.getPerspectiveTransform(rect, dst)
    return cv2.warpPerspective(image, m, (max_width, max_height))

def _deskew_document(img):
    h, w = img.shape[:2]
    if h < 200 or w < 200:
        return img

    ratio = h / 900.0 if h > 900 else 1.0
    small_h = int(h / ratio)
    small_w = int(w / ratio)
    small = cv2.resize(img, (small_w, small_h), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blur, 60, 180)

    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return img
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:15]

    page = None
    for c in contours:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(approx) == 4:
            area = cv2.contourArea(approx)
            if area > (small_h * small_w * 0.2):
                page = approx.reshape(4, 2).astype("float32")
                break
    if page is None:
        return img

    page *= ratio
    return _four_point_transform(img, page)

def preprocess_image(input_path, output_path):
    img = cv2.imread(input_path)
    if img is None:
        raise ValueError("Invalid image path")

    # 1. Perspective correction / deskew for photographed reports.
    img = _deskew_document(img)

    # 2. Resize (important for small lab text)
    img = cv2.resize(img, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)

    # 3. Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 4. Light denoising (document-safe)
    gray = cv2.bilateralFilter(gray, 9, 75, 75)

    # 5. Adaptive threshold (BEST for reports)
    thresh = cv2.adaptiveThreshold(
        gray,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        10
    )

    # 6. Ensure black text on white background
    if np.mean(thresh) < 127:
        thresh = cv2.bitwise_not(thresh)

    root, ext = os.path.splitext(output_path)
    ext_lower = ext.lower()
    supported_exts = {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"}
    if ext_lower not in supported_exts:
        output_path = root + ".png"

    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    cv2.imwrite(output_path, thresh)

    return output_path