---
name: facebook-post-drafter
description: Use when generating or drafting Facebook post content for product listings. Triggers on keywords like "traje de baño", "post", "publicar", "draft", "borrador", product images, or price/size info.
---

# Facebook Post Drafter

## Input format

User provides a short prompt with:
- Product description (may include emojis)
- Size
- Price
- Optional: delivery location (default: "Polígono 108 CTM o Macroplaza")
- Optional: product images (use them to enhance description)

## Content generation rules

1. **Language:** Always generate content in Spanish, even if prompt is English
2. **Structure:**
   - Opening: attractive product description (2-4 emojis)
   - Size: "Talla [size]"
   - Optional: 1-2 descriptive lines about the product
   - Price: "$[price]"
   - Delivery: "Entrego en Polígono 108 CTM o Macroplaza 📍"
   - Closing: "Mensaje para más info."
   - Final newline for Facebook UI alignment

3. **Emoji usage:** 2-4 emojis per post, relevant to product type
4. **Tone:** Friendly, appealing, feminine for swimwear; adapt for other products
5. **Image handling:** If images provided, include them in post order as shared

## Workflow

1. Receive prompt
2. Analyze if image(s) provided - use them to enhance description
3. Generate draft content in Spanish
4. **ALWAYS** present draft to user for validation before posting
5. User can approve or request changes
6. On approval: create temp file with content, run facebook-publisher CLI

## Example prompt:
"Hermoso traje de baño de 3 pzas talla M $260"

## Example generated draft:
```
Hermoso traje de baño de 3 piezas 🌸
Talla M

Ideal para lucir fresco y femenino este verano.

$260
Entrego en Polígono 108 CTM o Macroplaza 📍

Mensaje para más info.

```

## CLI usage (after approval):

### Text only:
```bash
echo "content" > /tmp/post.txt
set -a; . ./.env; set +a; ./bin/facebook-publisher.cmd publish --text-file /tmp/post.txt
```

### With image:
```bash
echo "content" > /tmp/post.txt
set -a; . ./.env; set +a; ./bin/facebook-publisher.cmd publish --text-file /tmp/post.txt --image path/to/image.png
```

### Dry run (optional, for validation):
```bash
set -a; . ./.env; set +a; ./bin/facebook-publisher.cmd publish --text-file /tmp/post.txt --dry-run
```
