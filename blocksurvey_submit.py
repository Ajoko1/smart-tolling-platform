#!/usr/bin/env python3
"""
BlockSurvey Submit Command
A custom Python automation script for submitting forms on BlockSurvey platform
Specifically designed for Code for Stacks contest submissions
"""

import argparse
import sys
import time
import requests
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from webdriver_manager.chrome import ChromeDriverManager
from selenium.webdriver.chrome.service import Service

class BlockSurveySubmitter:
    def __init__(self, email, github_url, headless=False, timeout=30):
        self.email = email
        self.github_url = github_url
        self.headless = headless
        self.timeout = timeout
        self.driver = None
        
        # BlockSurvey form URL (this would be the actual contest form URL)
        self.form_url = "https://blocksurvey.io/survey/code-for-stacks-submission"
    
    def setup_driver(self):
        """Initialize Chrome WebDriver with appropriate options"""
        try:
            chrome_options = Options()
            if self.headless:
                chrome_options.add_argument("--headless")
            chrome_options.add_argument("--no-sandbox")
            chrome_options.add_argument("--disable-dev-shm-usage")
            chrome_options.add_argument("--disable-gpu")
            chrome_options.add_argument("--window-size=1920,1080")
            
            # Setup ChromeDriver
            service = Service(ChromeDriverManager().install())
            self.driver = webdriver.Chrome(service=service, options=chrome_options)
            self.driver.implicitly_wait(10)
            
            print("✅ Chrome WebDriver initialized successfully")
            return True
            
        except Exception as e:
            print(f"❌ Failed to initialize WebDriver: {e}")
            return False
    
    def navigate_to_form(self):
        """Navigate to the BlockSurvey form"""
        try:
            print(f"🌐 Navigating to form: {self.form_url}")
            self.driver.get(self.form_url)
            
            # Wait for page to load
            WebDriverWait(self.driver, self.timeout).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )
            
            print("✅ Successfully navigated to BlockSurvey form")
            return True
            
        except Exception as e:
            print(f"❌ Failed to navigate to form: {e}")
            return False
    
    def fill_form_fields(self):
        """Fill out the form fields with provided data"""
        try:
            print("📝 Filling out form fields...")
            
            # Wait for form to be ready
            time.sleep(3)
            
            # Find and fill email field
            email_selectors = [
                "input[type='email']",
                "input[name*='email']",
                "input[placeholder*='email']",
                "input[id*='email']"
            ]
            
            email_field = None
            for selector in email_selectors:
                try:
                    email_field = WebDriverWait(self.driver, 5).until(
                        EC.presence_of_element_located((By.CSS_SELECTOR, selector))
                    )
                    break
                except:
                    continue
            
            if email_field:
                email_field.clear()
                email_field.send_keys(self.email)
                print(f"✅ Email field filled: {self.email}")
            else:
                print("⚠️  Email field not found")
            
            # Find and fill GitHub URL field
            github_selectors = [
                "input[name*='github']",
                "input[name*='url']",
                "input[name*='link']",
                "input[placeholder*='github']",
                "input[placeholder*='url']",
                "textarea[name*='github']",
                "textarea[name*='url']"
            ]
            
            github_field = None
            for selector in github_selectors:
                try:
                    github_field = WebDriverWait(self.driver, 5).until(
                        EC.presence_of_element_located((By.CSS_SELECTOR, selector))
                    )
                    break
                except:
                    continue
            
            if github_field:
                github_field.clear()
                github_field.send_keys(self.github_url)
                print(f"✅ GitHub URL field filled: {self.github_url}")
            else:
                print("⚠️  GitHub URL field not found")
            
            return True
            
        except Exception as e:
            print(f"❌ Failed to fill form fields: {e}")
            return False
    
    def submit_form(self):
        """Submit the form"""
        try:
            print("🚀 Submitting form...")
            
            # Find and click submit button
            submit_selectors = [
                "button[type='submit']",
                "input[type='submit']",
                "button[name*='submit']",
                "button:contains('Submit')",
                ".submit-btn",
                "#submit",
                "button.btn-primary"
            ]
            
            submit_button = None
            for selector in submit_selectors:
                try:
                    submit_button = WebDriverWait(self.driver, 5).until(
                        EC.element_to_be_clickable((By.CSS_SELECTOR, selector))
                    )
                    break
                except:
                    continue
            
            if submit_button:
                submit_button.click()
                print("✅ Form submitted successfully!")
                
                # Wait for submission confirmation
                time.sleep(5)
                
                # Look for success message
                success_selectors = [
                    ".success",
                    ".confirmation",
                    "[class*='success']",
                    "[class*='thank']"
                ]
                
                for selector in success_selectors:
                    try:
                        success_element = self.driver.find_element(By.CSS_SELECTOR, selector)
                        if success_element:
                            print("🎉 Submission confirmed!")
                            return True
                    except:
                        continue
                
                print("✅ Form submitted (confirmation pending)")
                return True
            else:
                print("❌ Submit button not found")
                return False
                
        except Exception as e:
            print(f"❌ Failed to submit form: {e}")
            return False
    
    def cleanup(self):
        """Close browser and cleanup resources"""
        if self.driver:
            self.driver.quit()
            print("🧹 Browser session closed")
    
    def submit(self):
        """Main submission workflow"""
        print("🚀 Starting BlockSurvey submission process...")
        print(f"📧 Email: {self.email}")
        print(f"🔗 GitHub URL: {self.github_url}")
        print(f"👤 Headless mode: {self.headless}")
        print("-" * 50)
        
        try:
            # Setup WebDriver
            if not self.setup_driver():
                return False
            
            # Navigate to form
            if not self.navigate_to_form():
                return False
            
            # Fill form fields
            if not self.fill_form_fields():
                return False
            
            # Submit form
            if not self.submit_form():
                return False
            
            print("\n🎉 BlockSurvey submission completed successfully!")
            return True
            
        except Exception as e:
            print(f"\n❌ Submission failed: {e}")
            return False
        
        finally:
            self.cleanup()

def main():
    """Main function to handle command line arguments and execute submission"""
    parser = argparse.ArgumentParser(
        description="BlockSurvey Submit Command - Automated form submission for Code for Stacks contest"
    )
    
    parser.add_argument(
        "--email", "-e",
        default="chineduajoko@yahoo.com",
        help="Email address to submit (default: chineduajoko@yahoo.com)"
    )
    
    parser.add_argument(
        "--github-url", "-g",
        default="https://github.com/Ajoko1/smart-tolling-platform/pull/1",
        help="GitHub URL to submit (default: Smart Tolling Platform PR)"
    )
    
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run browser in headless mode (invisible browser window)"
    )
    
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Timeout for waiting for elements in seconds (default: 30)"
    )
    
    args = parser.parse_args()
    
    # Create submitter instance
    submitter = BlockSurveySubmitter(
        email=args.email,
        github_url=args.github_url,
        headless=args.headless,
        timeout=args.timeout
    )
    
    # Execute submission
    success = submitter.submit()
    
    if success:
        print("\n✅ BlockSurvey submission completed successfully!")
        sys.exit(0)
    else:
        print("\n❌ BlockSurvey submission failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
