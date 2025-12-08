#!/usr/bin/env python3
"""
Fujifilm X-T50 Camera Availability Monitor

Checks camera availability on Calumet website and sends notifications
when the camera becomes available for purchase.
"""

import sys
import subprocess
import logging
import time
from datetime import datetime

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError as e:
    print(f"Error: Required Python package not found: {e}", file=sys.stderr)
    sys.exit(1)

# Configure logging to stdout for systemd journal
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

# Configuration
CAMERA_URL = "https://www.calumet.de/product/fujifilm-x-t50-silber"
NOT_AVAILABLE_TEXT = "Bald wieder lieferbar"
REQUEST_TIMEOUT = 30  # seconds
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"


def send_notification(title: str, message: str, urgency: str = "normal") -> None:
    """
    Send a desktop notification using notify-send.

    Args:
        title: Notification title
        message: Notification message
        urgency: Urgency level (low, normal, critical)
    """
    try:
        subprocess.run(
            [
                "notify-send",
                "--urgency", urgency,
                "--app-name", "Camera Monitor",
                title,
                message
            ],
            check=True,
            capture_output=True,
            text=True
        )
        logger.info(f"Notification sent: {title}")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to send notification: {e.stderr}")
    except FileNotFoundError:
        logger.error("notify-send command not found")


def check_availability() -> bool:
    """
    Check if the camera is available on the Calumet website.

    Looks specifically at the delivery-information section of the main product.
    The product is NOT available if we find class="delivery-storesoutofstock"
    or class="delivery-notavailable" in the main product section.

    Returns:
        True if camera is available, False otherwise

    Raises:
        requests.RequestException: If network request fails
    """
    headers = {"User-Agent": USER_AGENT}

    logger.info(f"Checking camera availability at {CAMERA_URL}")

    response = requests.get(CAMERA_URL, headers=headers, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, 'html.parser')

    # Find the main product delivery information container
    # This ensures we only check the actual product, not recommendations
    main_product_container = soup.find('div', class_='product-detail-delivery-information')

    if not main_product_container:
        # Fallback: try to find product-delivery-information
        main_product_container = soup.find('div', class_='product-delivery-information')

    if not main_product_container:
        logger.warning("Could not find main product delivery container, checking entire page")
        main_product_container = soup

    # Look for delivery-information elements within the main product container only
    delivery_info_sections = main_product_container.find_all('p', class_=lambda c: c and 'delivery-information' in c)

    has_bald_wieder = False
    for section in delivery_info_sections:
        if "Bald wieder lieferbar" in section.get_text():
            has_bald_wieder = True
            break

    # Check for positive availability indicators in delivery-information sections
    availability_indicators = []
    for section in delivery_info_sections:
        text = section.get_text()
        if "Versand aus einer Filiale" in text:
            availability_indicators.append("Versand aus einer Filiale")
        if "Auf Lager" in text:
            availability_indicators.append("Auf Lager")
        if "Sofort lieferbar" in text:
            availability_indicators.append("Sofort lieferbar")

    unavailable_elements = main_product_container.find_all('p', class_=lambda c: c and any(uc in ['delivery-storesoutofstock', 'delivery-notavailable'] for uc in (c.split() if c else [])))

    # Camera is available if we find ANY positive availability indicators
    # (even if some delivery options show "Bald wieder lieferbar" for other variants)
    is_available = len(availability_indicators) > 0

    logger.info(f"Page analysis:")
    logger.info(f"  - Unavailable elements found: {len(unavailable_elements)}")
    logger.info(f"  - 'Bald wieder lieferbar' in delivery sections: {has_bald_wieder}")
    logger.info(f"  - Availability indicators in delivery sections: {availability_indicators if availability_indicators else 'None'}")
    logger.info(f"  - Camera is {'AVAILABLE' if is_available else 'NOT AVAILABLE'}")

    return is_available


def check_availability_with_retry(max_retries: int = 3, retry_delay: int = 10) -> bool:
    """
    Check availability with retry logic for transient network failures.

    Args:
        max_retries: Maximum number of attempts
        retry_delay: Seconds to wait between retries

    Returns:
        True if camera is available, False otherwise

    Raises:
        requests.RequestException: If all retries fail
    """
    last_exception = None
    for attempt in range(max_retries):
        try:
            return check_availability()
        except requests.RequestException as e:
            last_exception = e
            if attempt < max_retries - 1:
                logger.warning(f"Attempt {attempt + 1}/{max_retries} failed: {e}")
                logger.info(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                logger.error(f"All {max_retries} attempts failed")
    raise last_exception


def main() -> int:
    """
    Main function to check camera availability and send notifications.

    Returns:
        0 on success, 1 on error
    """
    try:
        logger.info("=== Camera Monitor Check Starting ===")

        is_available = check_availability_with_retry()

        if is_available:
            logger.info("✓ Camera IS available!")
            send_notification(
                "📷 Fujifilm X-T50 Available!",
                f"The silver X-T50 is now available at Calumet!\n{CAMERA_URL}",
                urgency="critical"
            )
        else:
            logger.info("✗ Camera is not yet available")
            # Optionally send a low-priority notification for "still checking" status
            # Uncomment if you want periodic confirmations that monitoring is working
            # send_notification(
            #     "Camera Monitor",
            #     "Fujifilm X-T50 still not available",
            #     urgency="low"
            # )

        logger.info("=== Camera Monitor Check Complete ===")
        return 0

    except requests.Timeout:
        logger.error(f"Request timed out after {REQUEST_TIMEOUT} seconds")
        send_notification(
            "Camera Monitor Error",
            "Failed to check availability: Request timeout",
            urgency="normal"
        )
        return 1

    except requests.RequestException as e:
        logger.error(f"Network error: {e}")
        send_notification(
            "Camera Monitor Error",
            f"Failed to check availability: {str(e)[:100]}",
            urgency="normal"
        )
        return 1

    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        send_notification(
            "Camera Monitor Error",
            f"Unexpected error: {str(e)[:100]}",
            urgency="normal"
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
