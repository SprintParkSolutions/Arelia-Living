import { LightningElement } from 'lwc';
import IdcLogo from '@salesforce/resourceUrl/Arelia_Footer_Logo';
import InstagramIcon from '@salesforce/resourceUrl/InstagramIcon';
import FacebookIcon from '@salesforce/resourceUrl/FacebookIcon';
import LinkedinIcon from '@salesforce/resourceUrl/LinkedinIcon';

import RESIDENTIAL_URL from '@salesforce/label/c.Residential_URL';
import COMMERCIAL_URL from '@salesforce/label/c.Commercial_URL';
import HOSPITALITY_URL from '@salesforce/label/c.Hospitality_URL';

import INSTAGRAM_URL from '@salesforce/label/c.Instagram_URL';
import FACEBOOK_URL from '@salesforce/label/c.Facebook_URL';
import LINKEDIN_URL from '@salesforce/label/c.LinkedIn_URL';

export default class IdcFooterComponent extends LightningElement {
    logoUrl = IdcLogo;
    instagramIcon = InstagramIcon;
    facebookIcon = FacebookIcon;
    linkedinIcon = LinkedinIcon;

    residentialUrl = RESIDENTIAL_URL;
    commercialUrl = COMMERCIAL_URL;
    hospitalityUrl = HOSPITALITY_URL;

    instagramUrl = INSTAGRAM_URL;
    facebookUrl = FACEBOOK_URL;
    linkedinUrl = LINKEDIN_URL;
}