import { LightningElement } from 'lwc';
import IdcLogo from '@salesforce/resourceUrl/Arelia_Footer_Logo';
import InstagramIcon from '@salesforce/resourceUrl/InstagramIcon';
import FacebookIcon from '@salesforce/resourceUrl/FacebookIcon';
import LinkedinIcon from '@salesforce/resourceUrl/LinkedinIcon';

export default class IdcFooterComponent extends LightningElement {
    logoUrl = IdcLogo;
    instagramUrl = InstagramIcon;
    facebookUrl = FacebookIcon;
    linkedinIcon = LinkedinIcon;
}